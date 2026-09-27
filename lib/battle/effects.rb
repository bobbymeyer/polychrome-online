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
      when "jump" then jump(ctx, actor, target, effect)
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
      return ctx.emit(:miss, actor: actor["id"], target: target["id"], reason: "steal_failed", roll: roll, needed: chance) unless success

      drop = drops.find { |d| (pick -= d["chance"]).negative? }
      target["stolen"] = true
      (ctx.state["stolen"] ||= []) << drop["item"]
      ctx.emit(:steal, actor: actor["id"], target: target["id"], item: drop["item"], name: drop.fetch("name", drop["item"]), roll: roll, needed: chance)
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
      needed = hit_chance(ctx, actor, target)
      hit, roll = ctx.rng.d100(needed)
      unless auto_hit?(ctx, target) || hit
        return ctx.emit(:miss, actor: actor["id"], target: target["id"], reason: "evaded", roll: roll, needed: needed)
      end

      crit_needed = crit_chance(ctx, actor, target)
      crit, crit_roll = ctx.rng.d100(crit_needed)
      base = (ctx.stat(actor, "atk") + ctx.stat(actor, "str")) * effect.fetch("power", 100) / 100
      amount = mitigate(vary(ctx, base), ctx.stat(target, "def"))
      amount *= 2 if crit
      amount /= 2 if target["defending"]
      # Typed after every draw, so the stream doesn't depend on the chart.
      return if typed(ctx, actor, target, type_of(ctx, effect), amount, crit: crit, roll: crit_roll, needed: crit_needed)

      ctx.remove_status(target, "sleep", reason: "woke") if ctx.alive?(target)
      counter(ctx, actor, target)
    end

    # "terrain" is the type of where the fight is.
    def type_of(ctx, effect)
      effect["type"] == "terrain" ? ctx.state.fetch("terrain", "normal") : effect["type"]
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

      ctx.emit(:counter, actor: target["id"], target: actor["id"], roll: roll, needed: COUNTER_CHANCE)
      ctx.countering = true
      physical(ctx, target, actor, { "primitive" => "physical", "power" => 100 })
    ensure
      ctx.countering = false if struck
    end

    # jump(power): the actor leaves the field, out of reach, and lands on the
    # target on its next turn (Battle::Resolver#land) for power% of a blow.
    def jump(ctx, actor, target, effect)
      ctx.add_status(actor, "airborne", 2)
      status = actor["statuses"].find { |st| st["kind"] == "airborne" }
      status["target"] = target["id"]
      status["power"] = effect.fetch("power", 200)
      ctx.emit(:jump, actor: actor["id"], target: target["id"])
    end

    # elemental(type, power, hits): power scaled by mag, softened by mdef,
    # then by the type chart. Magic never misses.
    def elemental(ctx, actor, target, effect)
      typed(ctx, actor, target, type_of(ctx, effect), magic_amount(ctx, actor, target, effect))
    end

    # Deal damage of a type (nil: typeless) through the chart and the
    # target's affinities. Returns true when it didn't land as damage
    # (no effect, or absorbed).
    def typed(ctx, actor, target, type, amount, crit: false, roll: nil, needed: nil)
      percent = Types.effectiveness(type, target)
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
      dice = chance < 100 ? { roll: roll, needed: chance } : {}

      if target["status_immune"].include?(kind) || Types.status_immune?(target, kind)
        ctx.emit(:miss, actor: actor["id"], target: target["id"], reason: "immune", status: kind)
      elsif !landed
        ctx.emit(:miss, actor: actor["id"], target: target["id"], reason: "resisted", status: kind, **dice)
      else
        ctx.add_status(target, kind, effect.fetch("duration", 3), **dice)
      end
    end

    # heal(power): power scaled by the caster's mag.
    def heal(ctx, actor, target, effect)
      amount = [ vary(ctx, scale_by_mag(ctx, actor, effect.fetch("power"))), 1 ].max
      ctx.restore_hp(target, amount, actor: actor["id"])
    end

    # drain(power): non-elemental magic damage returned to the caster as HP.
    def drain(ctx, actor, target, effect)
      amount = [ magic_amount(ctx, actor, target, effect), 1 ].max
      taken = [ amount, target["hp"] ].min
      ctx.deal_damage(target, amount, actor: actor["id"], drain: true)
      ctx.restore_hp(actor, taken, source: target["id"], drain: true)
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

    # revive(fraction): fraction is a percent of max HP.
    def revive(ctx, target, effect)
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
        ctx.emit(:flee, actor: actor["id"], success: true, roll: roll, needed: chance)
        ctx.end_by_flight
      else
        ctx.emit(:flee, actor: actor["id"], success: false, reason: "blocked", roll: roll, needed: chance)
      end
    end

    # End-of-turn upkeep for a unit: poison, then duration ticks.
    REGEN_DIVISOR = 16

    def upkeep(ctx, unit)
      if ctx.status?(unit, "poison")
        ctx.deal_damage(unit, [ unit["stats"]["max_hp"] / POISON_DIVISOR, 1 ].max, status: "poison")
        return unless ctx.alive?(unit)
      end
      passives = Array(unit["passives"])
      if passives.include?("regen") && unit["hp"] < unit["stats"]["max_hp"]
        ctx.restore_hp(unit, [ unit["stats"]["max_hp"] / REGEN_DIVISOR, 1 ].max, regen: true)
      end
      if passives.include?("mp_regen") && unit["mp"] < unit["stats"]["max_mp"]
        ctx.restore_mp(unit, [ unit["stats"]["max_mp"] / REGEN_DIVISOR, 1 ].max, regen: true)
      end

      unit["statuses"].each { |s| s["turns"] -= 1 }
      unit["statuses"].select { |s| s["turns"] <= 0 }.map { |s| s["kind"] }.each do |kind|
        ctx.remove_status(unit, kind, reason: "wore_off")
      end

      unit["buffs"].each { |b| b["turns"] -= 1 }
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
      mitigate(vary(ctx, scale_by_mag(ctx, actor, effect.fetch("power"))), ctx.stat(target, "mdef"))
    end

    def scale_by_mag(ctx, actor, power)
      power * (ctx.stat(actor, "mag") + 16) / 16
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
