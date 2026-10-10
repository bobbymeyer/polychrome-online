# frozen_string_literal: true

module Battle
  # Working set for a single Resolver.apply call: a private copy of the state,
  # the RNG rehydrated from it, and the event list being produced. Shared
  # queries and state mutations that always emit an event live here so every
  # path (abilities, statuses, GM overrides) reports changes the same way.
  class Context
    attr_reader :state, :rng, :events
    attr_accessor :countering, :reacting
    # Creatures summoned by the move being resolved: they act once it's done
    # (Battle::Resolver#summon).
    attr_reader :arrivals
    # What a move set off for after it's done (Battle::Resolver#follow_up):
    # [:quick, unit] goes again, [:mimic, unit] copies an ally's last move.
    attr_reader :follow_ups
    # Who has had a turn so far this round, in order (Patience).
    attr_reader :acted
    # Reactions the move being resolved called for (a script's "when" rules): they come once it's done
    # (Battle::Resolver#react). [{ "unit", "rule", "trigger", "target" }]
    attr_reader :reactions

    def initialize(state, rng: Rng.new(state["rng"]))
      @state = state
      @rng = rng
      @events = []
      @arrivals = []
      @follow_ups = []
      @acted = []
      @reactions = []
    end

    # A moment a script's "when" rule waits for: the first rule for it is queued, once per unit per
    # move. Never from within a reaction: reactions don't set off reactions.
    def queue_reaction(unit, trigger, by: nil, target: nil)
      return if reacting || over? || unit["gone"]
      return if reactions.any? { |r| r["unit"] == unit["id"] && r["trigger"] == trigger }

      index = AI.reaction(self, unit, trigger, by: by) or return
      reactions << { "unit" => unit["id"], "rule" => index, "trigger" => trigger, "target" => target }
    end

    def finish
      state["rng"] = rng.state
      [ state, events ]
    end

    def emit(type, **data)
      events << { "type" => type.to_s }.merge(data.transform_keys(&:to_s))
    end

    # --- queries ----------------------------------------------------------

    def units
      state["units"]
    end

    def unit(id)
      units.find { |u| u["id"] == id } or raise InvalidAction, "no unit #{id.inspect}"
    end

    def find_unit(id)
      units.find { |u| u["id"] == id }
    end

    # The battle's types (Battle::Types); battles from before worlds had
    # their own ran on the base world's.
    def types
      state["types"] || Types::DEFAULT
    end

    def type_list
      Types.list(types)
    end

    def ability(id)
      state["abilities"][id] or raise InvalidAction, "no ability #{id.inspect}"
    end

    def item(id)
      state.fetch("items", {})[id] or raise InvalidAction, "the party has no #{id.inspect}"
    end

    def over?
      state["status"] != "input"
    end

    # A unit that has left the field (GM "dismiss") is out of play for good:
    # not alive, not fallen, not a target, never counted.
    def alive?(u)
      u["hp"].positive? && !u["gone"]
    end

    def status?(u, kind)
      u["statuses"].any? { |s| s["kind"] == kind }
    end

    def disabled?(u)
      DISABLING_STATUSES.any? { |kind| status?(u, kind) }
    end

    # basis: stats to use in place of the unit's own, before buffs (a
    # mastered ability cast outside its job keeps its job's stats).
    def stat(u, name, basis: nil)
      effective_stats(u, basis: basis).fetch(name)
    end

    def effective_stats(u, basis: nil)
      stats = basis ? u["stats"].merge(basis) : u["stats"]
      Stats::Derivation.effective(stats, buffs: u["buffs"] + Conditions.buffs(state), statuses: u["statuses"].map { |s| s["kind"] })
    end

    def allies(u, alive: true)
      units.select { |o| o["side"] == u["side"] && !o["gone"] && (!alive || alive?(o)) }
    end

    # Who u can aim at: the other side's living units, less any off the
    # field (unless the move has the reach for them: a Ranger's shot).
    def opponents(u, reach: false)
      units.select { |o| o["side"] != u["side"] && alive?(o) && (reach || !out_of_reach?(o)) }
    end

    # The other side's living units this move can find (State.reaches?).
    def within_reach(u, ability)
      units.select { |o| o["side"] != u["side"] && alive?(o) && State.reaches?(ability, o) }
    end

    def out_of_reach?(u)
      OUT_OF_REACH_STATUSES.any? { |kind| status?(u, kind) }
    end

    def side(name)
      units.select { |u| u["side"] == name && !u["gone"] }
    end

    def hp_percent(u)
      u["hp"] * 100 / u["stats"]["max_hp"]
    end

    def revives?(ability)
      State.revives?(ability)
    end

    # Can this unit pay for and use the ability right now?
    def usable?(u, ability)
      State.usable?(u, ability)
    end

    def ability_cost(ability)
      State.ability_cost(ability)
    end

    # --- mutations that always emit --------------------------------------

    # A shield takes blows out of its own amount first; poison goes round it.
    def deal_damage(target, amount, **extra)
      amount = shielded(target, amount) unless extra[:status]
      return if amount.zero?

      target["hp"] = [ target["hp"] - amount, 0 ].max
      emit(:damage, target: target["id"], amount: amount, hp: target["hp"], **extra)
      # Struck by an opponent: what it does when hit (a counter), once it's standing or not.
      striker = extra[:actor] && unit(extra[:actor])
      interrupt(target, amount)
      if striker && striker["side"] != target["side"]
        target["last_hit_by"] = striker["id"] unless extra[:status]
        queue_reaction(target, "hit", by: extra[:damage_type], target: striker["id"])
        free_from(target, striker, extra[:damage_type]) unless extra[:status]
      end
      return unless target["hp"].zero?

      reraise = status?(target, "reraise")
      knock_out(target)
      reraise ? reraised(target) : second_wind(target)
    end

    # Reraise: knocked out, back up at once at a quarter HP, and it's gone.
    RERAISE_FRACTION = 25

    def reraised(target)
      return if over? || target["gone"]

      emit(:reraise, target: target["id"])
      revive(target, target["stats"]["max_hp"] * RERAISE_FRACTION / 100)
    end

    def shielded(target, amount)
      shield = target["statuses"].find { |s| s["kind"] == "shield" }
      return amount unless shield

      absorbed = [ shield["amount"].to_i, amount ].min
      shield["amount"] = shield["amount"].to_i - absorbed
      emit(:shielded, target: target["id"], absorbed: absorbed, left: shield["amount"])
      remove_status(target, "shield", reason: "broken") if shield["amount"].zero?
      amount - absorbed
    end

    # Once a battle, a unit with Second Wind gets back up at a quarter HP
    # when knocked down (never once the fight is over).
    def second_wind(target)
      return if over? || target["second_wind_used"] || !Array(target["passives"]).include?("second_wind")

      target["second_wind_used"] = true
      target["hp"] = [ target["stats"]["max_hp"] / 4, 1 ].max
      emit(:second_wind, target: target["id"], hp: target["hp"])
    end

    def restore_mp(target, amount, **extra)
      target["mp"] = [ target["mp"] + amount, target["stats"]["max_mp"] ].min
      emit(:mp_restored, target: target["id"], amount: amount, mp: target["mp"], **extra)
    end

    def restore_hp(target, amount, **extra)
      target["hp"] = [ target["hp"] + amount, target["stats"]["max_hp"] ].min
      emit(:heal, target: target["id"], amount: amount, hp: target["hp"], **extra)
    end

    def knock_out(target)
      let_go(target, reason: "holder_fell")
      give_back(target)
      target["hp"] = 0
      mask = target["statuses"].find { |s| s["kind"] == "masked" }
      Masks.take_off(self, target, mask, spent: false) if mask
      target["statuses"] = []
      target["buffs"] = []
      target["defending"] = false
      emit(:ko, target: target["id"])
      # Its last breath, and what its side does when one of them falls.
      queue_reaction(target, "falls")
      units.each { |ally| queue_reaction(ally, "ally_falls") if ally["side"] == target["side"] && ally != target && alive?(ally) }
      # What it called to its side goes with it: the adds are the boss's.
      units.each { |creature| send_home(creature) if creature.dig("summoned", "by") == target["id"] && !creature["gone"] }
      # A summoned creature isn't left lying there to be raised: down, it's gone.
      return unless target["summoned"] && !target["gone"]

      target["gone"] = true
      emit(:unit_left, unit: target["id"], name: target["name"], summoned: true)
    end

    # A summoned creature leaves the field (its turns up, its summoner down).
    def send_home(creature)
      let_go(creature, reason: "holder_left")
      creature["gone"] = true
      creature["statuses"] = []
      creature["buffs"] = []
      emit(:unit_left, unit: creature["id"], name: creature["name"], summoned: true)
    end

    def revive(target, hp)
      target["hp"] = hp.clamp(1, target["stats"]["max_hp"])
      emit(:revive, target: target["id"], hp: target["hp"])
    end

    def add_status(target, kind, turns, **extra)
      existing = target["statuses"].find { |s| s["kind"] == kind }
      if existing
        existing["turns"] = [ existing["turns"], turns ].max
      else
        target["statuses"] << { "kind" => kind, "turns" => turns }
      end
      emit(:status_applied, target: target["id"], status: kind, turns: turns, **extra)
    end

    def remove_status(target, kind, reason:)
      return unless status?(target, kind)

      gone = target["statuses"].select { |s| s["kind"] == kind }
      target["statuses"] -= gone
      emit(:status_expired, target: target["id"], status: kind, reason: reason)
      Masks.take_off(self, target, gone.first, spent: true) if kind == "masked"
    end

    # A move winding up that can be interrupted (its "interrupt": a share of
    # the user's max HP) is, once that much damage has come in since it
    # began: it's lost, and the user is down for a turn, stunned.
    def interrupt(unit, amount)
      winding = unit["statuses"].find { |s| s["kind"] == "charging" && s["interrupt"].to_i.positive? } or return
      winding["taken"] = winding["taken"].to_i + amount
      return if winding["taken"] < unit["stats"]["max_hp"] * winding["interrupt"] / 100 || !alive?(unit)

      unit["statuses"].delete(winding)
      emit(:interrupted, unit: unit["id"], ability: winding.dig("ability", "id"), taken: winding["taken"])
      add_status(unit, "down", 1) unless status?(unit, "down")
    end

    # What a thief took from the party's bag comes back to it: the thief
    # fell, or the party won the field (Effects#lift).
    def give_back(thief)
      taken = thief.delete("pilfered")
      return if taken.nil? || taken.empty?

      taken.each { |id| state["items"][id]["count"] += 1 if state.dig("items", id) }
      emit(:recovered, unit: thief["id"], items: taken, names: taken.map { |id| state.dig("items", id, "name") || id })
    end

    # The next wave of enemies comes on, if there's one waiting (State.build's
    # waves). Returns true when it did.
    def next_wave
      reserves = state["reserves"]
      return false if reserves.nil? || reserves.empty?

      wave = reserves.shift
      state.delete("reserves") if reserves.empty?
      units.concat(wave)
      emit(:wave, units: wave.map { |u| u["id"] }, names: wave.map { |u| u["name"] }, left: reserves.size)
      true
    end

    # Whoever this unit holds (the grab primitive) is let go: it fell, or left the field.
    def let_go(holder, reason:)
      units.each do |u|
        held = u["statuses"].find { |s| s["kind"] == "held" }
        remove_status(u, "held", reason: reason) if held && held["by"] == holder["id"]
      end
    end

    # A blow on a holder from the other side breaks the grip on whoever of
    # the striker's side it holds, if it's the kind of blow that does
    # ("breaks": any, "hit", or a type). Torn free, they lose tear% of
    # their max HP: the grip's damage, not the striker's.
    def free_from(holder, striker, type)
      units.each do |u|
        held = u["statuses"].find { |s| s["kind"] == "held" }
        next unless held && held["by"] == holder["id"] && u["side"] == striker["side"] && alive?(u)
        next unless held.fetch("breaks", "hit") == "hit" || held["breaks"] == type

        remove_status(u, "held", reason: "freed")
        tear = u["stats"]["max_hp"] * held.fetch("tear", 0).to_i / 100
        deal_damage(u, tear, status: "held") if tear.positive?
      end
    end

    # A stacking status's count (0 when it isn't on).
    def stacks(u, kind)
      u["statuses"].find { |s| s["kind"] == kind }&.fetch("stacks", 1).to_i
    end

    # A boss whose HP has crossed one of its lines becomes its next form, in
    # the order its phases are written: what it was called and looked like,
    # its script, its stats (the HP it has left carries over, plus what the
    # phase restores). A new script starts fresh. Checked wherever the end
    # is, after every stroke; never once the fight is over.
    def enter_phases
      side("enemy").each do |u|
        phases = u["phases"]
        next unless phases&.any? && alive?(u) && hp_percent(u) < phases.first["hp_below"]

        phase = phases.first
        form = phase["becomes"]
        was = u["name"]
        # Someone (an antagonist, a named boss) wears the form as a mask: their name and face stay.
        kept = u["named"] ? %w[id side phases name image named] : %w[id side phases]
        u.merge!(form.except(*kept))
        u["phases"] = phases.drop(1)
        u.delete("fired")
        u["hp"] = u["hp"].clamp(1, form["stats"]["max_hp"])
        u["mp"] = u["mp"].clamp(0, form["stats"]["max_mp"])
        emit(:phase, actor: u["id"], was: was, name: u["name"], form: form["name"], line: phase["say"], music: form["music"])
        # What the phase gives back: a heal, seen as any heal is.
        restored = form["stats"]["max_hp"] * phase["restore"] / 100
        restore_hp(u, restored, phase: true) if restored.positive?
      end
    end

    # Decide whether the battle has ended. Defeat is checked first: a party
    # that falls on the same stroke as the last enemy has not won.
    def check_end
      return if over?

      enter_phases
      if side("party").reject { |u| u["guest"] }.none? { |u| alive?(u) }
        state["status"] = "defeat"
        emit(:defeat)
      elsif side("enemy").none? { |u| alive?(u) } && next_wave
        nil # the next wave is on the field: it isn't over
      elsif side("enemy").none? { |u| alive?(u) }
        state["status"] = "victory"
        # Who left the field rather than fall (sent off, or a summon gone home): a victory over
        # nobody is the enemy getting away, and a boss that left hasn't been beaten.
        enemies = units.select { |u| u["side"] == "enemy" } # side() leaves out the gone
        emit(:victory, rewards: rewards, drops: roll_drops, fell: enemies.any? { |u| !u["gone"] }, gone: enemies.select { |u| u["gone"] }.map { |u| u["id"] })
      end
    end

    # Each defeated enemy drops at most one item: its drop table is tried in
    # order with the battle's RNG, so loot is part of the replay too.
    def roll_drops
      side("enemy").filter_map do |enemy|
        drop = enemy["drops"].find { |d| rng.percent?(d["chance"]) }
        drop && drop["item"]
      end
    end

    def end_by_flight
      state["status"] = "fled"
    end

    def rewards
      side("enemy").each_with_object(Hash.new(0)) do |u, total|
        u["rewards"].each { |k, v| total[k] += v }
      end.to_h
    end
  end
end
