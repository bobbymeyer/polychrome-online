# frozen_string_literal: true

module Battle
  # Working set for a single Resolver.apply call: a private copy of the state,
  # the RNG rehydrated from it, and the event list being produced. Shared
  # queries and state mutations that always emit an event live here so every
  # path (abilities, statuses, GM overrides) reports changes the same way.
  class Context
    attr_reader :state, :rng, :events

    def initialize(state, rng: Rng.new(state["rng"]))
      @state = state
      @rng = rng
      @events = []
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

    def ability(id)
      state["abilities"][id] or raise InvalidAction, "no ability #{id.inspect}"
    end

    def over?
      state["status"] != "input"
    end

    def alive?(u)
      u["hp"].positive?
    end

    def status?(u, kind)
      u["statuses"].any? { |s| s["kind"] == kind }
    end

    def disabled?(u)
      DISABLING_STATUSES.any? { |kind| status?(u, kind) }
    end

    def stat(u, name)
      effective_stats(u).fetch(name)
    end

    def effective_stats(u)
      Stats::Derivation.effective(u["stats"], buffs: u["buffs"], statuses: u["statuses"].map { |s| s["kind"] })
    end

    def allies(u, alive: true)
      units.select { |o| o["side"] == u["side"] && (!alive || alive?(o)) }
    end

    def opponents(u)
      units.select { |o| o["side"] != u["side"] && alive?(o) }
    end

    def side(name)
      units.select { |u| u["side"] == name }
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

    def deal_damage(target, amount, **extra)
      target["hp"] = [ target["hp"] - amount, 0 ].max
      emit(:damage, target: target["id"], amount: amount, hp: target["hp"], **extra)
      knock_out(target) if target["hp"].zero?
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
    end

    def revive(target, hp)
      target["hp"] = hp.clamp(1, target["stats"]["max_hp"])
      emit(:revive, target: target["id"], hp: target["hp"])
    end

    def add_status(target, kind, turns)
      existing = target["statuses"].find { |s| s["kind"] == kind }
      if existing
        existing["turns"] = [ existing["turns"], turns ].max
      else
        target["statuses"] << { "kind" => kind, "turns" => turns }
      end
      emit(:status_applied, target: target["id"], status: kind, turns: turns)
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

      if side("party").none? { |u| alive?(u) }
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
