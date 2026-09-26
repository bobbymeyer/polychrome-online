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
  # for allies), highest_hp, self.
  module AI
    CONDITIONS = %w[self_hp_below ally_hp_below ally_ko round_multiple chance].freeze
    STRATEGIES = %w[random lowest_hp highest_hp self].freeze

    module_function

    # Returns [ability, target_id_or_nil]. Falls back to Attack.
    def choose(ctx, unit)
      unit["ai"].each do |rule|
        ability = ctx.state["abilities"][rule["use"]]
        next unless ability && ctx.usable?(unit, ability)
        next unless conditions_met?(ctx, unit, rule.fetch("if", {}))

        target = pick_target(ctx, unit, ability, rule["target"])
        next if target == :none

        return [ability, target]
      end

      [ctx.ability("attack"), nil]
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
               when "lowest_hp" then pool.min_by { |u| [ctx.hp_percent(u), u["hp"]] }
               when "highest_hp" then pool.max_by { |u| [u["hp"], -ctx.units.index(u)] }
               else ctx.rng.pick(pool)
               end
      chosen["id"]
    end
  end
end
