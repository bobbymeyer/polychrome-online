# frozen_string_literal: true

module Battle
  # FF-style enemy scripts: an ordered list of rules, first match wins.
  #
  #   [
  #     { "if" => { "self_hp_below" => 30 }, "use" => "cure", "target" => "self" },
  #     { "if" => { "chance" => 40 }, "use" => "fire" },
  #     { "use" => "attack" }
  #   ]
  #
  # Conditions (all must hold): self_hp_below, ally_hp_below (percent),
  # ally_ko (true), round_multiple (n), chance (percent).
  # Target strategies: random (default for opponents), lowest_hp (default
  # for allies), highest_hp, self, last_hit (whoever's blow last landed on
  # it, else at random; a move that takes turns to go off finds them again
  # as it goes off, so landing a blow first turns it).
  #
  # A rule can be "once" => true (it fires once a battle: a self-buff that
  # isn't recast every turn, a one-time move) and "say" => "…" (a line the
  # creature says as the rule fires: the telegraph before a charged blow,
  # the taunt at low HP). The resolver marks fired rules on the unit
  # ("fired", by index) and emits the line; choosing changes nothing.
  #
  # A rule with "when" is a reaction, never chosen on the creature's turn:
  # "hit" (struck by an opponent; "by" => a type narrows it to blows of
  # that type), "struck" (an opponent's blow up close is about to land: it
  # answers first, and the blow comes only if its striker is still standing
  # and free to swing; Resolver#forestalled?), "ally_falls" (one of its
  # side goes down), "falls" (its own last breath: a final attack as it
  # goes down). Its conditions still
  # apply. The reaction comes at once, free of its charge, and reactions
  # never set off reactions (Context#queue_reaction, Resolver#react).
  module AI
    CONDITIONS = %w[self_hp_below ally_hp_below ally_ko round_multiple chance].freeze
    STRATEGIES = %w[random lowest_hp highest_hp self last_hit].freeze
    TRIGGERS = %w[hit struck ally_falls falls].freeze

    module_function

    # Returns [ability, target_id_or_nil, rule_index_or_nil]. Falls back to Attack.
    def choose(ctx, unit)
      unit["ai"].each_with_index do |rule, index|
        next if rule["when"] # a reaction waits for its moment
        next if rule["once"] && unit.fetch("fired", []).include?(index)

        ability = ctx.state["abilities"][rule["use"]]
        next unless ability && ctx.usable?(unit, ability)
        next unless conditions_met?(ctx, unit, rule.fetch("if", {}))

        target = pick_target(ctx, unit, ability, rule["target"])
        next if target == :none

        return [ ability, target, index ]
      end

      [ ctx.ability("attack"), nil, nil ]
    end

    # The reaction a moment calls for: the first "when" rule for the trigger (and the type that struck,
    # for a hit) whose conditions hold and that isn't spent. Returns its index, or nil.
    def reaction(ctx, unit, trigger, by: nil)
      unit["ai"].each_with_index do |rule, index|
        next unless rule["when"] == trigger
        next if rule["by"] && rule["by"] != by
        next if rule["once"] && unit.fetch("fired", []).include?(index)
        next unless ctx.state["abilities"][rule["use"]]
        next unless conditions_met?(ctx, unit, rule.fetch("if", {}))

        return index
      end
      nil
    end

    # The rule chosen is used: one that fires once is spent, and what it says is said.
    def fire(ctx, unit, index)
      rule = index && unit["ai"][index] or return
      (unit["fired"] ||= []) << index if rule["once"]
      ctx.emit(:says, actor: unit["id"], line: rule["say"]) unless rule["say"].to_s.empty?
    end

    def conditions_met?(ctx, unit, conditions)
      unknown = conditions.keys - CONDITIONS
      raise Error, "unknown AI conditions: #{unknown.join(', ')}" if unknown.any?

      # Deterministic conditions first; chance is drawn only if they pass.
      conditions.except("chance").all? { |name, arg| check(ctx, unit, name, arg) } &&
        (!conditions.key?("chance") || ctx.rng.percent?(conditions["chance"]))
    end

    def check(ctx, unit, name, arg)
      case name
      when "self_hp_below" then ctx.hp_percent(unit) < arg
      when "ally_hp_below" then ctx.allies(unit).any? { |a| ctx.hp_percent(a) < arg }
      when "ally_ko" then ctx.allies(unit, alive: false).any? { |a| !ctx.alive?(a) } == arg
      when "round_multiple" then (ctx.state["round"] % arg).zero?
      end
    end

    # Returns a unit id, nil (area/random targeting, or let execution pick),
    # or :none when the rule has nobody to act on.
    def pick_target(ctx, unit, ability, strategy)
      return :none if strategy && !STRATEGIES.include?(strategy)

      case ability["target"]
      when "self" then unit["id"]
      when "single_enemy"
        choose_from(ctx, ctx.opponents(unit), strategy || "random", unit)
      when "single_ally"
        pool = if ctx.revives?(ability)
                 ctx.allies(unit, alive: false).reject { |a| ctx.alive?(a) }
        else
                 ctx.allies(unit)
        end
        choose_from(ctx, pool, strategy || "lowest_hp", unit)
      else
        ctx.revives?(ability) && ctx.allies(unit, alive: false).all? { |a| ctx.alive?(a) } ? :none : nil
      end
    end

    def choose_from(ctx, pool, strategy, unit)
      return unit["id"] if strategy == "self"
      return :none if pool.empty?

      chosen = case strategy
      when "lowest_hp" then pool.min_by { |u| [ ctx.hp_percent(u), u["hp"] ] }
      when "highest_hp" then pool.max_by { |u| [ u["hp"], -ctx.units.index(u) ] }
      when "last_hit" then pool.find { |u| u["id"] == unit["last_hit_by"] } || ctx.rng.pick(pool)
      else ctx.rng.pick(pool)
      end
      chosen["id"]
    end
  end
end
