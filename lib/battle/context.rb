# frozen_string_literal: true

module Battle
  # Working set for a single Resolver.apply call: a private copy of the state,
  # the RNG rehydrated from it, and the event list being produced. Shared
  # queries and state mutations that always emit an event live here so every
  # path (abilities, statuses, GM overrides) reports changes the same way.
  class Context
    attr_reader :state, :rng, :events
    attr_accessor :countering
    # Creatures summoned by the move being resolved: they act once it's done
    # (Battle::Resolver#summon).
    attr_reader :arrivals

    def initialize(state, rng: Rng.new(state["rng"]))
      @state = state
      @rng = rng
      @events = []
      @arrivals = []
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
      Stats::Derivation.effective(stats, buffs: u["buffs"], statuses: u["statuses"].map { |s| s["kind"] })
    end

    def allies(u, alive: true)
      units.select { |o| o["side"] == u["side"] && !o["gone"] && (!alive || alive?(o)) }
    end

    # Who u can aim at: the other side's living units, less any off the field.
    def opponents(u)
      units.select { |o| o["side"] != u["side"] && alive?(o) && !out_of_reach?(o) }
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
      return unless target["hp"].zero?

      knock_out(target)
      second_wind(target)
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
      target["hp"] = 0
      target["statuses"] = []
      target["buffs"] = []
      target["defending"] = false
      emit(:ko, target: target["id"])
      # A summoned creature isn't left lying there to be raised: down, it's gone.
      return unless target["summoned"] && !target["gone"]

      target["gone"] = true
      emit(:unit_left, unit: target["id"], name: target["name"], summoned: true)
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

      target["statuses"].reject! { |s| s["kind"] == kind }
      emit(:status_expired, target: target["id"], status: kind, reason: reason)
    end

    # Decide whether the battle has ended. Defeat is checked first: a party
    # that falls on the same stroke as the last enemy has not won.
    def check_end
      return if over?

      if side("party").reject { |u| u["guest"] }.none? { |u| alive?(u) }
        state["status"] = "defeat"
        emit(:defeat)
      elsif side("enemy").none? { |u| alive?(u) }
        state["status"] = "victory"
        emit(:victory, rewards: rewards, drops: roll_drops)
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
