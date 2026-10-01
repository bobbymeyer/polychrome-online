# frozen_string_literal: true

module Battle
  # The mechanic primitives (§3.1). Each function applies one hit of one
  # effect from actor to target and emits the events that describe it.
  #
  # All arithmetic is integer. RNG draws happen in a fixed order per
  # primitive (hit, crit, variance) so tuning a number never reorders the
  # stream for anything that follows.
  module Effects
    BASE_HIT = 95
    HIT_FLOOR = 50
    HIT_CEILING = 99
    BASE_CRIT = 5
    CRIT_CEILING = 25
    POISON_DIVISOR = 16

    module_function

    def apply(ctx, actor, target, effect)
      effect = grudging(actor, effect)
      case effect["primitive"]
      when "physical" then physical(ctx, actor, target, effect)
      when "elemental" then elemental(ctx, actor, target, effect)
      when "status" then status(ctx, actor, target, effect)
      when "heal" then heal(ctx, actor, target, effect)
      when "drain" then drain(ctx, actor, target, effect)
      when "buff" then modify(ctx, target, effect, 1)
      when "debuff" then modify(ctx, target, effect, -1)
      when "revive" then revive(ctx, target, effect)
      when "escape" then escape(ctx, actor)
      when "cleanse" then cleanse(ctx, actor, target, effect)
      when "steal" then steal(ctx, actor, target, effect)
      when "scan" then scan(ctx, target)
      when "jump" then away(ctx, actor, target, effect.merge("who" => "self", "power" => effect.fetch("power", 200)))
      when "away" then away(ctx, actor, target, effect)
      when "shield" then shield(ctx, actor, target, effect)
      when "imbue" then imbue(ctx, target, effect)
      when "percent" then percent(ctx, actor, target, effect)
      when "sap" then sap(ctx, actor, target, effect)
      when "summon" then summon(ctx, actor, effect)
      else raise Error, "unknown primitive #{effect['primitive']}"
      end
    end

    # steal(chance): take one of the target's drops, weighted by its drop
    # chances. Faster thieves steal more often. Each target can be robbed
    # once; the item is the party's whatever the battle's outcome. Draws the
    # success roll and the pick every time, so the stream doesn't depend on
    # whether it worked.
    def steal(ctx, actor, target, effect)
      drops = target.fetch("drops", [])
      if drops.empty? || target["stolen"]
        return ctx.emit(:miss, actor: actor["id"], target: target["id"], reason: "nothing_to_steal")
      end

      chance = (effect.fetch("chance", 50) + (ctx.stat(actor, "agi") - ctx.stat(target, "agi"))).clamp(5, 95)
      success, roll = ctx.rng.d100(chance)
      pick = ctx.rng.int(drops.sum { |d| d["chance"] })
      return ctx.emit(:miss, actor: actor["id"], target: target["id"], reason: "steal_failed", roll: roll, needed: Rng.target(chance)) unless success

      drop = drops.find { |d| (pick -= d["chance"]).negative? }
      target["stolen"] = true
      (ctx.state["stolen"] ||= []) << drop["item"]
      ctx.emit(:steal, actor: actor["id"], target: target["id"], item: drop["item"], name: drop.fetch("name", drop["item"]), roll: roll, needed: Rng.target(chance))
    end

    # scan: the target's types, its own affinities, what it shrugs off, and
    # its HP.
    # No RNG: knowledge always works.
    def scan(ctx, target)
      ctx.emit(:scan, target: target["id"], types: target.fetch("types", []), affinities: target.fetch("affinities", {}),
                      status_immune: target.fetch("status_immune", []), hp: target["hp"], max_hp: target["stats"]["max_hp"])
    end

    # cleanse(kind): cure one status, or every harmful one. No RNG: a cure
    # always works. Curing nothing is a miss, so the table sees it happen.
    def cleanse(ctx, actor, target, effect)
      kinds = effect["kind"] ? [ effect["kind"] ] : HARMFUL_STATUSES
      cured = kinds.select { |kind| ctx.status?(target, kind) }
      return ctx.emit(:miss, actor: actor["id"], target: target["id"], reason: "nothing_to_cure") if cured.empty?

      cured.each { |kind| ctx.remove_status(target, kind, reason: "cured") }
    end

    # physical(power, hits): (atk + str) * power%, softened by def.
    def physical(ctx, actor, target, effect)
      # Non-short-circuit `|`: the hit roll is drawn even on an auto-hit.
      chance = hit_chance(ctx, actor, target)
      hit, roll = ctx.rng.d100(chance)
      unless auto_hit?(ctx, target) || hit
        return ctx.emit(:miss, actor: actor["id"], target: target["id"], reason: "evaded", roll: roll, needed: Rng.target(chance))
      end

      crit_chance = crit_chance(ctx, actor, target)
      crit, crit_roll = ctx.rng.d100(crit_chance)
      basis = effect["basis"]
      base = (ctx.stat(actor, "atk", basis: basis) + ctx.stat(actor, "str", basis: basis)) * effect.fetch("power", 100) / 100
      amount = against(ctx, target, effect, mitigate(vary(ctx, base), ctx.stat(target, "def")))
      amount *= 2 if crit
      amount /= 2 if target["defending"]
      # Typed after every draw, so the stream doesn't depend on the chart.
      return if typed(ctx, actor, target, type_of(ctx, effect), amount, crit: crit, roll: crit_roll, needed: Rng.target(crit_chance), recoil: effect["recoil"])

      if ctx.alive?(target)
        ctx.remove_status(target, "sleep", reason: "woke")
        ctx.remove_status(target, "confuse", reason: "came_to")
      end
      counter(ctx, actor, target)
    end

    # "terrain" is the type of where the fight is.
    def type_of(ctx, effect)
      effect["type"] == "terrain" ? ctx.state.fetch("terrain") { ctx.type_list.first } : effect["type"]
    end

    # Counter (a passive): hit by an enemy's blow and still standing, a unit
    # sometimes strikes straight back. A counter never sets off another.
    COUNTER_CHANCE = 30

    def counter(ctx, actor, target)
      return if ctx.countering || ctx.over?
      return unless Array(target["passives"]).include?("counter") && target["side"] != actor["side"]
      return unless ctx.alive?(target) && ctx.alive?(actor) && !ctx.disabled?(target)

      struck, roll = ctx.rng.d100(COUNTER_CHANCE)
      return unless struck

      ctx.emit(:counter, actor: target["id"], target: actor["id"], roll: roll, needed: Rng.target(COUNTER_CHANCE))
      ctx.countering = true
      physical(ctx, target, actor, { "primitive" => "physical", "power" => 100, "type" => target["attack_type"] }.compact)
    ensure
      ctx.countering = false if struck
    end

    # away(who, duration, power, chance, type): someone leaves the field, out
    # of reach and out of the fight, for `duration` of their own turns
    # (Battle::Resolver#come_back).
    #   who "self":   the user goes (Jump, Hide). With power, it comes back
    #                 on the target for power% of a blow of that type: that
    #                 is its turn. Without, it comes back and acts.
    #   who "target": the target is sent away (Banish, Knockback) and loses
    #                 the turns it's gone for. Against an opponent the chance
    #                 is reduced by spr, like a status, and a unit can be
    #                 immune ("away" in its status_immune).
    def away(ctx, actor, target, effect)
      who = effect.fetch("who", "target")
      goer = who == "self" ? actor : target
      power = effect.fetch("power", 0)
      if who == "target" && target["side"] != actor["side"]
        return ctx.emit(:miss, actor: actor["id"], target: target["id"], reason: "immune", status: "away") if target["status_immune"].include?("away")

        chance = effect.fetch("chance", 100)
        chance = chance * 100 / (100 + ctx.stat(target, "spr")) if chance < 100
        came_in, roll = ctx.rng.d100(chance)
        unless came_in || chance >= 100
          return ctx.emit(:miss, actor: actor["id"], target: target["id"], reason: "resisted", status: "away", roll: roll, needed: Rng.target(chance))
        end
      end

      turns = effect.fetch("duration", 1)
      goer["statuses"].reject! { |s| OUT_OF_REACH_STATUSES.include?(s["kind"]) }
      goer["statuses"] << { "kind" => "away", "turns" => turns, "left" => turns, "self" => who == "self",
                            "power" => power, "target" => (target["id"] if power.positive?) }.merge(effect.slice("type", "basis")).compact
      if who == "self" && power.positive?
        ctx.emit(:jump, actor: actor["id"], target: target["id"], turns: turns)
      else
        ctx.emit(:away, actor: actor["id"], unit: goer["id"], turns: turns)
      end
    end

    # elemental(type, power, hits): power scaled by mag, softened by mdef,
    # then by the type chart. Magic never misses.
    def elemental(ctx, actor, target, effect)
      typed(ctx, actor, target, type_of(ctx, effect), against(ctx, target, effect, magic_amount(ctx, actor, target, effect)), recoil: effect["recoil"])
    end

    # grudge: power grows with the user's missing HP, up to grudge% more
    # at the brink.
    def grudging(actor, effect)
      return effect unless effect["grudge"]

      missing = actor["stats"]["max_hp"] - actor["hp"]
      effect.merge("power" => effect.fetch("power", 100) * (100 + (effect["grudge"] * missing / actor["stats"]["max_hp"])) / 100)
    end

    # against/bonus: bonus% (default ×2) when the target has the status or
    # type named, or is undead or a boss.
    def against(ctx, target, effect, amount)
      trait = effect["against"]
      return amount unless trait

      matched = ctx.status?(target, trait) || target.fetch("types", []).include?(trait) || (AGAINST_TRAITS.include?(trait) && target[trait])
      matched ? amount * effect.fetch("bonus", 200) / 100 : amount
    end

    # Deal damage of a type (nil: typeless) through the chart and the
    # target's affinities. Returns true when it didn't land as damage
    # (no effect, or absorbed).
    def typed(ctx, actor, target, type, amount, crit: false, roll: nil, needed: nil, recoil: nil)
      percent = Types.effectiveness(type, target, ctx.types)
      if percent == 0 # rubocop:disable Style/NumericPredicate -- may be :absorb
        ctx.emit(:miss, actor: actor["id"], target: target["id"], reason: "immune", damage_type: type)
        return true
      end

      amount = [ percent == :absorb ? amount : amount * percent / 100, 1 ].max
      if percent == :absorb
        ctx.restore_hp(target, amount, actor: actor["id"], damage_type: type, absorbed: true)
        return true
      end

      ctx.emit(:crit, actor: actor["id"], target: target["id"], roll: roll, needed: needed) if crit
      extra = type ? { damage_type: type, effectiveness: percent } : {}
      ctx.deal_damage(target, amount, actor: actor["id"], crit: crit, **extra)
      if recoil.to_i.positive? && ctx.alive?(actor) && actor != target
        ctx.deal_damage(actor, [ amount * recoil / 100, 1 ].max, recoil: true)
      end
      false
    end

    # status(kind, chance, duration). Against opponents the chance is
    # reduced by spr; chance >= 100 always lands. Duration counts the
    # target's own turns.
    def status(ctx, actor, target, effect)
      kind = effect["kind"]
      chance = effect.fetch("chance", 100)
      chance = chance * 100 / (100 + ctx.stat(target, "spr")) if chance < 100 && target["side"] != actor["side"]
      came_in, roll = ctx.rng.d100(chance)
      landed = came_in || chance >= 100
      dice = chance < 100 ? { roll: roll, needed: Rng.target(chance) } : {}

      if target["status_immune"].include?(kind) || Types.status_immune?(target, kind, ctx.types)
        ctx.emit(:miss, actor: actor["id"], target: target["id"], reason: "immune", status: kind)
      elsif !landed
        ctx.emit(:miss, actor: actor["id"], target: target["id"], reason: "resisted", status: kind, **dice)
      else
        ctx.add_status(target, kind, effect.fetch("duration", 3), **dice)
      end
    end

    # heal(power): power scaled by the caster's mag. An item's heal is the
    # same in anyone's hands, as if at ITEM_MAG: a Potion doesn't care who
    # opens it. The undead take it as damage instead.
    ITEM_MAG = 16

    def heal(ctx, actor, target, effect)
      power = effect.fetch("power")
      scaled = effect["item"] ? by_mag(power, ITEM_MAG) : scale_by_mag(ctx, actor, power, effect["basis"])
      amount = [ vary(ctx, scaled), 1 ].max
      return ctx.deal_damage(target, amount, actor: actor["id"], undead: true) if target["undead"]

      ctx.restore_hp(target, amount, actor: actor["id"])
    end

    # drain(power): non-elemental magic damage returned to the caster as HP.
    # Against the undead it runs backwards: they're fed, the caster pays.
    def drain(ctx, actor, target, effect)
      amount = [ magic_amount(ctx, actor, target, effect), 1 ].max
      giver, taker = target["undead"] ? [ actor, target ] : [ target, actor ]
      taken = [ amount, giver["hp"] ].min
      ctx.deal_damage(giver, amount, actor: actor["id"], drain: true)
      ctx.restore_hp(taker, taken, source: giver["id"], drain: true) if ctx.alive?(taker)
    end

    # shield(power, duration): a barrier of power-scaled-by-mag HP that
    # damage comes out of first (Context#deal_damage). A new one replaces it.
    def shield(ctx, actor, target, effect)
      amount = [ scale_by_mag(ctx, actor, effect.fetch("power"), effect["basis"]), 1 ].max
      target["statuses"].reject! { |s| s["kind"] == "shield" }
      ctx.add_status(target, "shield", effect.fetch("duration", 3), amount: amount)
      target["statuses"].find { |s| s["kind"] == "shield" }["amount"] = amount
    end

    # imbue(type, duration): the target's Attack strikes with the type.
    def imbue(ctx, target, effect)
      target["statuses"].reject! { |s| s["kind"] == "imbued" }
      ctx.add_status(target, "imbued", effect.fetch("duration", 3), damage_type: effect["type"])
      target["statuses"].find { |s| s["kind"] == "imbued" }["type"] = effect["type"]
    end

    # percent(power, chance): power% of the target's current HP, whatever its
    # defence or type. It never knocks anyone out; a boss takes a quarter.
    def percent(ctx, actor, target, effect)
      chance = effect.fetch("chance", 100)
      came_in, roll = ctx.rng.d100(chance)
      unless came_in || chance >= 100
        return ctx.emit(:miss, actor: actor["id"], target: target["id"], reason: "evaded", roll: roll, needed: Rng.target(chance))
      end

      share = effect.fetch("power") / (target["boss"] ? 4 : 1)
      amount = [ target["hp"] * share / 100, target["hp"] - 1 ].min
      return ctx.emit(:miss, actor: actor["id"], target: target["id"], reason: "no_effect") unless amount.positive?

      ctx.deal_damage(target, amount, actor: actor["id"], percent: share)
    end

    # summon(creature, duration, power): the creature comes to the user's
    # side, a guest under its own script, its Str, Mag and Atk scaled by
    # power%. It acts as soon as the move is done, and leaves after its
    # duration (Battle::Resolver#arrive, #take_turn). It earns nothing and
    # drops nothing.
    SUMMON_STATS = %w[str mag atk].freeze

    def summon(ctx, actor, effect)
      spec = State.normalize(ctx.state.fetch("summons", {}).fetch(effect["creature"]))
      power = effect.fetch("power", 100)
      spec["stats"] = spec["stats"].to_h { |k, v| [ k, SUMMON_STATS.include?(k) ? v * power / 100 : v ] }
      taken = ctx.units.map { |u| u["id"] }
      n = (1..).find { |i| !taken.include?("#{spec['id']}_#{i}") }
      creature = State.unit(spec.merge("id" => "#{spec['id']}_#{n}", "rewards" => {}, "drops" => []), actor["side"], ctx.type_list)
      creature["guest"] = true if actor["side"] == "party"
      creature["summoned"] = { "by" => actor["id"], "left" => effect.fetch("duration", 1) }
      ctx.units << creature
      ctx.arrivals << creature
      ctx.emit(:summoned, actor: actor["id"], unit: creature["id"], name: creature["name"], side: creature["side"],
                          image: creature["image"], turns: effect.fetch("duration", 1))
    end

    # sap(power, keep): MP taken, scaled by mag and softened by mdef; keep%
    # of what was taken goes to the user.
    def sap(ctx, actor, target, effect)
      amount = [ magic_amount(ctx, actor, target, effect) / 4, 1 ].max
      taken = [ amount, target["mp"] ].min
      return ctx.emit(:miss, actor: actor["id"], target: target["id"], reason: "no_mp") unless taken.positive?

      target["mp"] -= taken
      ctx.emit(:mp_lost, actor: actor["id"], target: target["id"], amount: taken, mp: target["mp"])
      kept = taken * effect.fetch("keep", 0) / 100
      ctx.restore_mp(actor, kept, source: target["id"]) if kept.positive?
    end

    # buff/debuff(stat, amount, duration): amount is a percent. A new
    # modifier of the same direction on the same stat replaces the old one.
    def modify(ctx, target, effect, sign)
      stat = effect["stat"]
      amount = effect.fetch("amount").abs * sign
      turns = effect.fetch("duration", 3)
      target["buffs"].reject! { |b| b["stat"] == stat && (b["amount"] <=> 0) == sign }
      target["buffs"] << { "stat" => stat, "amount" => amount, "turns" => turns }
      ctx.emit(:buff_applied, target: target["id"], stat: stat, amount: amount, turns: turns)
    end

    # revive(fraction): fraction is a percent of max HP. On the living
    # undead it's that much damage instead.
    def revive(ctx, target, effect)
      if target["undead"] && ctx.alive?(target)
        return ctx.deal_damage(target, [ target["stats"]["max_hp"] * effect.fetch("fraction", 25) / 100, 1 ].max, undead: true)
      end

      if ctx.alive?(target)
        return ctx.emit(:miss, target: target["id"], reason: "not_ko")
      end

      ctx.revive(target, target["stats"]["max_hp"] * effect.fetch("fraction", 25) / 100)
    end

    # escape: the whole side leaves, guaranteed, unless the battle forbids it.
    def escape(ctx, actor)
      if ctx.state["escapable"]
        ctx.emit(:flee, actor: actor["id"], success: true)
        ctx.end_by_flight
      else
        ctx.emit(:flee, actor: actor["id"], success: false, reason: "no_escape")
      end
    end

    # The ordinary Flee command: a chance based on relative speed.
    def attempt_flee(ctx, actor)
      unless ctx.state["escapable"]
        return ctx.emit(:flee, actor: actor["id"], success: false, reason: "no_escape")
      end

      mine = average_agi(ctx, ctx.allies(actor))
      theirs = average_agi(ctx, ctx.opponents(actor))
      chance = (50 + (mine - theirs) * 2).clamp(10, 95)
      escaped, roll = ctx.rng.d100(chance)
      if escaped
        ctx.emit(:flee, actor: actor["id"], success: true, roll: roll, needed: Rng.target(chance))
        ctx.end_by_flight
      else
        ctx.emit(:flee, actor: actor["id"], success: false, reason: "blocked", roll: roll, needed: Rng.target(chance))
      end
    end

    # End-of-turn upkeep for a unit: poison, then duration ticks.
    REGEN_DIVISOR = 16
    # MP comes back more slowly than HP: a caster with it still has to choose
    # when to spend.
    MP_REGEN_DIVISOR = 32

    # held: the buffs and statuses the unit had when its turn began (nil for
    # all of them). One it gave itself during the turn starts counting next turn.
    def upkeep(ctx, unit, held: nil)
      counts = ->(entry) { held.nil? || held.any? { |h| h.equal?(entry) } }
      if ctx.status?(unit, "poison")
        ctx.deal_damage(unit, [ unit["stats"]["max_hp"] / POISON_DIVISOR, 1 ].max, status: "poison")
        return unless ctx.alive?(unit)
      end
      passives = Array(unit["passives"])
      if passives.include?("regen") && unit["hp"] < unit["stats"]["max_hp"]
        ctx.restore_hp(unit, [ unit["stats"]["max_hp"] / REGEN_DIVISOR, 1 ].max, regen: true)
      end
      if passives.include?("mp_regen") && unit["mp"] < unit["stats"]["max_mp"]
        ctx.restore_mp(unit, [ unit["stats"]["max_mp"] / MP_REGEN_DIVISOR, 1 ].max, regen: true)
      end

      # Away and charging count their own turns (Battle::Resolver).
      unit["statuses"].each { |s| s["turns"] -= 1 if counts.(s) && !%w[away charging].include?(s["kind"]) }
      unit["statuses"].select { |s| s["turns"] <= 0 }.map { |s| s["kind"] }.each do |kind|
        ctx.remove_status(unit, kind, reason: "wore_off")
        # Doom's count runs out: down they go, shield or no.
        ctx.deal_damage(unit, unit["hp"], status: "doom") if kind == "doom" && ctx.alive?(unit)
      end

      unit["buffs"].each { |b| b["turns"] -= 1 if counts.(b) }
      expired, unit["buffs"] = unit["buffs"].partition { |b| b["turns"] <= 0 }
      expired.each do |b|
        ctx.emit(:buff_expired, target: unit["id"], stat: b["stat"], amount: b["amount"])
      end
    end

    # --- formula helpers ---------------------------------------------------

    def hit_chance(ctx, actor, target)
      chance = (BASE_HIT + (ctx.stat(actor, "agi") - ctx.stat(target, "agi")) / 2).clamp(HIT_FLOOR, HIT_CEILING)
      ctx.status?(actor, "blind") ? chance / 2 : chance
    end

    def crit_chance(ctx, actor, target)
      (BASE_CRIT + [ ctx.stat(actor, "agi") - ctx.stat(target, "agi"), 0 ].max / 4).clamp(0, CRIT_CEILING)
    end

    # Sleeping or paralysed targets cannot dodge. The hit roll is still
    # drawn so the RNG stream does not depend on the target's condition.
    def auto_hit?(ctx, target)
      ctx.disabled?(target)
    end

    def magic_amount(ctx, actor, target, effect)
      mitigate(vary(ctx, scale_by_mag(ctx, actor, effect.fetch("power"), effect["basis"])), ctx.stat(target, "mdef"))
    end

    # A spell's power grows with the caster's mag: ×2 at 16, ×3 at 28, ×4
    # at 40, so a mage's growth and gear are felt as a fighter's are.
    def scale_by_mag(ctx, actor, power, basis = nil)
      by_mag(power, ctx.stat(actor, "mag", basis: basis))
    end

    def by_mag(power, mag)
      power * (mag + 8) / 12
    end

    # Variance in [224/256, 255/256].
    def vary(ctx, amount)
      amount * (224 + ctx.rng.int(32)) / 256
    end

    def mitigate(amount, defense)
      amount * 100 / (100 + defense)
    end

    def average_agi(ctx, units)
      return 0 if units.empty?

      units.sum { |u| ctx.stat(u, "agi") } / units.size
    end
  end
end
