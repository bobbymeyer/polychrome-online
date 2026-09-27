# frozen_string_literal: true

module Battle
  # Battle::Resolver.apply(state, action) -> [new_state, events]
  #
  # Pure: the input state is never mutated, there is no I/O, and all
  # randomness comes from the RNG state stored inside the battle state.
  #
  # Rounds are Dragon Quest style. Party members submit commands; once every
  # member able to act has one, the whole round executes in speed order and
  # control returns to input. Actions:
  #
  #   { type: "command", actor: "hero", command: { kind: "ability", ability: "fire", target: "goblin_a" } }
  #   { type: "command", actor: "hero", command: { kind: "item", item: "potion", target: "hero" } }
  #   { type: "command", actor: "hero", command: { kind: "defend" } }
  #   { type: "command", actor: "hero", command: { kind: "flee" } }
  #   { type: "timeout" }          # input timer expired: fill gaps with defaults and run
  #   { type: "gm_override", op: "...", ... }   # see #gm_override
  #
  # A missing command defaults to the unit's last command if it is still
  # usable (never an item: nobody spends the party's items by default),
  # otherwise Attack on a random target.
  class Resolver
    GM_OPS = %w[auto execute_round set_hp set_mp add_status remove_status end_battle add_unit dismiss].freeze
    END_RESULTS = %w[victory defeat fled].freeze

    def self.apply(state, action)
      new(state).apply(action)
    end

    def initialize(state)
      @ctx = Context.new(State.normalize(state))
    end

    def apply(action)
      action = State.normalize(action)
      raise InvalidAction, "battle is over (#{state['status']})" if ctx.over?

      case action["type"]
      when "command" then command(action)
      when "timeout" then timeout
      when "gm_override" then gm_override(action)
      else raise InvalidAction, "unknown action type #{action['type'].inspect}"
      end

      ctx.finish
    end

    private

    attr_reader :ctx

    def state
      ctx.state
    end

    # --- input phase -------------------------------------------------------

    # Party members who must submit a command before the round can run.
    def awaiting
      State.able_to_act(state)
    end

    def missing_inputs
      awaiting - state["inputs"].keys
    end

    def command(action)
      unit = ctx.unit(action["actor"])
      raise InvalidAction, "#{unit['id']} is not a party member" unless unit["side"] == "party"
      raise InvalidAction, "#{unit['id']} cannot act" unless awaiting.include?(unit["id"])

      cmd = validate_command(unit, action.fetch("command") { raise InvalidAction, "command missing" })
      state["inputs"][unit["id"]] = cmd
      ctx.emit(:command_accepted, actor: unit["id"])
      run_round if missing_inputs.empty?
    end

    def validate_command(unit, cmd)
      kind = cmd.fetch("kind", "ability")
      raise InvalidAction, "unknown command #{kind.inspect}" unless COMMAND_KINDS.include?(kind)
      return { "kind" => "defend" } if kind == "defend"

      if kind == "flee"
        raise InvalidAction, "this battle cannot be fled" unless state["escapable"]

        return { "kind" => "flee" }
      end
      return validate_item(unit, cmd) if kind == "item"

      ability = ctx.ability(cmd.fetch("ability", "attack"))
      raise InvalidAction, "#{unit['id']} does not know #{ability['id']}" unless unit["abilities"].include?(ability["id"])
      raise InvalidAction, "#{unit['id']} is silenced" if ability["kind"] == "magic" && ctx.status?(unit, "silence")
      raise InvalidAction, "#{unit['id']} lacks MP for #{ability['id']}" if unit["mp"] < ctx.ability_cost(ability)

      target = cmd["target"]
      validate_target(unit, ability, target) if target
      command = { "kind" => "ability", "ability" => ability["id"], "target" => target }
      # The timing meter: stopped on the mark, the move lands harder.
      cmd["timing"] == "perfect" ? command.merge("timing" => "perfect") : command
    end

    def validate_item(unit, cmd)
      item = ctx.item(cmd["item"])
      raise InvalidAction, "no #{item['name']} left" unless State.items_left(state, item["id"], except: unit["id"]).positive?

      target = cmd["target"]
      validate_target(unit, item, target) if target
      { "kind" => "item", "item" => item["id"], "target" => target }
    end

    def validate_target(unit, ability, target_id)
      target = ctx.unit(target_id)
      case ability["target"]
      when "single_enemy"
        raise InvalidAction, "#{target_id} is not an enemy" if target["side"] == unit["side"]
        raise InvalidAction, "#{target_id} is down" unless ctx.alive?(target)
      when "single_ally"
        raise InvalidAction, "#{target_id} is not an ally" unless target["side"] == unit["side"]
        raise InvalidAction, "#{target_id} is down" unless ctx.alive?(target) || ctx.revives?(ability)
      end
    end

    def default_command(unit)
      last = unit["last_command"]&.except("timing") # a Perfect is earned each round
      return last if last && still_valid?(unit, last)

      { "kind" => "ability", "ability" => "attack", "target" => nil }
    end

    def still_valid?(unit, cmd)
      case cmd["kind"]
      when "defend" then true
      when "flee" then state["escapable"]
      when "item" then false
      else ctx.usable?(unit, ctx.ability(cmd["ability"]))
      end
    end

    def fill_defaults
      missing_inputs.map do |id|
        state["inputs"][id] = default_command(ctx.unit(id))
        id
      end
    end

    def timeout
      ctx.emit(:timeout, defaulted: fill_defaults)
      run_round
    end

    # --- GM overrides ------------------------------------------------------
    #
    #   { op: "auto", unit: id }                      default command for an absent player
    #   { op: "auto", units: [id, ...] }              the same for several at once (one log line)
    #   { op: "execute_round" }                       run now; missing inputs get defaults
    #   { op: "set_hp", unit: id, value: n }
    #   { op: "set_mp", unit: id, value: n }
    #   { op: "add_status", unit: id, status: kind, turns: n }
    #   { op: "remove_status", unit: id, status: kind }
    #   { op: "end_battle", result: "victory" | "defeat" | "fled" }
    #
    # Every override emits a gm_override event first, then the ordinary
    # events describing its consequences. Optional "note" is carried along.
    def gm_override(action)
      op = action["op"]
      raise InvalidAction, "unknown GM op #{op.inspect}" unless GM_OPS.include?(op)

      send(:"gm_#{op}", action)
    end

    def gm_event(action, **data)
      ctx.emit(:gm_override, op: action["op"], note: action["note"], **data)
    end

    def gm_auto(action)
      if action["units"]
        units = Array(action["units"]).map { |id| ctx.unit(id) }
        raise InvalidAction, "auto needs at least one unit" if units.empty?
      else
        units = [ ctx.unit(action["unit"]) ]
      end
      units.each do |unit|
        raise InvalidAction, "#{unit['id']} is not awaiting input" unless missing_inputs.include?(unit["id"])

        state["inputs"][unit["id"]] = default_command(unit)
      end
      if action["units"]
        gm_event(action, units: units.map { |u| u["id"] }, commands: units.map { |u| state["inputs"][u["id"]] })
      else
        gm_event(action, unit: units.first["id"], command: state["inputs"][units.first["id"]])
      end
      run_round if missing_inputs.empty?
    end

    def gm_execute_round(action)
      gm_event(action, defaulted: fill_defaults)
      run_round
    end

    def gm_set_hp(action)
      unit = ctx.unit(action["unit"])
      value = Integer(action.fetch("value")).clamp(0, unit["stats"]["max_hp"])
      was_alive = ctx.alive?(unit)
      gm_event(action, unit: unit["id"], hp: value)
      if value.zero?
        ctx.knock_out(unit) if was_alive
      elsif was_alive
        unit["hp"] = value
      else
        ctx.revive(unit, value)
      end
      ctx.check_end
    end

    def gm_set_mp(action)
      unit = ctx.unit(action["unit"])
      unit["mp"] = Integer(action.fetch("value")).clamp(0, unit["stats"]["max_mp"])
      gm_event(action, unit: unit["id"], mp: unit["mp"])
    end

    def gm_add_status(action)
      unit = ctx.unit(action["unit"])
      kind = action["status"]
      raise InvalidAction, "unknown status #{kind.inspect}" unless STATUSES.include?(kind)
      raise InvalidAction, "#{unit['id']} is down" unless ctx.alive?(unit)

      gm_event(action, unit: unit["id"], status: kind)
      ctx.add_status(unit, kind, Integer(action.fetch("turns", 3)))
      state["inputs"].delete(unit["id"]) if ctx.disabled?(unit)
    end

    def gm_remove_status(action)
      unit = ctx.unit(action["unit"])
      gm_event(action, unit: unit["id"], status: action["status"])
      ctx.remove_status(unit, action["status"], reason: "gm")
    end

    def gm_end_battle(action)
      result = action["result"]
      raise InvalidAction, "unknown result #{result.inspect}" unless END_RESULTS.include?(result)

      gm_event(action, result: result)
      state["status"] = result
      case result
      when "victory" then ctx.emit(:victory, rewards: ctx.rewards, drops: ctx.roll_drops)
      when "defeat"
        # The party has fallen: whoever was still standing goes down too.
        ctx.side("party").select { |u| ctx.alive?(u) }.each { |u| ctx.knock_out(u) }
        ctx.emit(:defeat)
      when "fled" then ctx.emit(:flee, success: true)
      end
    end

    # A unit joins mid-fight: reinforcements for the enemy, or a guest who
    # fights beside the party under its own script. The spec is an engine
    # unit spec (a Bestiary entry's); "abilities" adds any the battle's
    # library doesn't have yet. A name already on the field gets the next
    # letter, like the rest of its kind.
    def gm_add_unit(action)
      side = action["side"] == "party" ? "party" : "enemy"
      spec = State.normalize(action.fetch("unit") { raise InvalidAction, "add_unit needs a unit" })
      Hash(action["abilities"]).each do |id, ability|
        next if state["abilities"].key?(id)

        ability = State.normalize(ability).merge("id" => id)
        begin
          State.validate_ability!(ability)
        rescue ArgumentError => e
          raise InvalidAction, e.message
        end
        state["abilities"][id] = ability
      end

      base_id = spec.fetch("id") { raise InvalidAction, "the unit needs an id" }.to_s
      base_name = spec.fetch("name", base_id).to_s
      taken = ctx.units.map { |u| u["id"] }
      kin = taken.any? { |t| t == base_id || t.match?(/\A#{Regexp.escape(base_id)}_[a-z]\z/) }
      lettered = ("a".."z").map { |l| [ "#{base_id}_#{l}", "#{base_name} #{l.upcase}" ] }
      id, name = (kin ? lettered : [ [ base_id, base_name ] ]).find { |candidate, _| !taken.include?(candidate) }
      raise InvalidAction, "too many #{base_name}s on the field" unless id

      begin
        unit = State.unit(spec.merge("id" => id, "name" => name), side)
      rescue ArgumentError => e
        raise InvalidAction, e.message
      end
      missing = unit["abilities"] - state["abilities"].keys
      raise InvalidAction, "#{name} knows unknown abilities: #{missing.join(', ')}" if missing.any?

      unit["guest"] = true if side == "party"
      ctx.units << unit
      gm_event(action, unit: id, side: side)
      ctx.emit(:unit_joined, unit: id, name: name, side: side, guest: side == "party")
    end

    # A unit leaves the field: an enemy runs or surrenders, a guest goes
    # their own way. It counts for nothing: no EXP, no drops. If it was the
    # last enemy standing, the party has won.
    def gm_dismiss(action)
      unit = ctx.unit(action["unit"])
      raise InvalidAction, "#{unit['name']} is a party member" if unit["side"] == "party" && !unit["guest"]
      raise InvalidAction, "#{unit['name']} has already gone" if unit["gone"]

      gm_event(action, unit: unit["id"])
      unit["gone"] = true
      unit["statuses"] = []
      unit["buffs"] = []
      ctx.emit(:unit_left, unit: unit["id"], name: unit["name"])
      ctx.check_end
    end

    # --- round execution ---------------------------------------------------

    def run_round
      inputs = state["inputs"]
      ctx.emit(:round_start, round: state["round"])

      ctx.side("party").each do |u|
        u["defending"] = inputs.dig(u["id"], "kind") == "defend" && ctx.alive?(u)
      end

      order = turn_order
      ctx.emit(:turn_order, order: order)
      order.each do |id|
        break if ctx.over?

        take_turn(ctx.unit(id), inputs[id])
        ctx.check_end
      end

      close_round(inputs)
    end

    # Speed order: agi plus up to a quarter of agi at random. Ties go to
    # the unit listed first.
    def turn_order
      ctx.units.each_with_index.filter_map do |u, index|
        next unless ctx.alive?(u)

        agi = ctx.stat(u, "agi")
        [ -(agi + ctx.rng.int(agi / 4 + 1)), index, u["id"] ]
      end.sort.map(&:last)
    end

    def take_turn(unit, cmd)
      return unless ctx.alive?(unit) # KO'd earlier this round: no turn at all

      ctx.emit(:turn_start, unit: unit["id"])
      blocking = DISABLING_STATUSES.find { |kind| ctx.status?(unit, kind) }
      if blocking
        ctx.emit(:turn_skipped, unit: unit["id"], reason: blocking)
      elsif unit["side"] == "enemy" || unit["guest"]
        ability, target = AI.choose(ctx, unit)
        use_ability(unit, ability, target)
      elsif cmd.nil?
        ctx.emit(:turn_skipped, unit: unit["id"], reason: "no_command")
      else
        perform(unit, cmd)
      end

      Effects.upkeep(ctx, unit) if ctx.alive?(unit) && !ctx.over?
      ctx.emit(:turn_end, unit: unit["id"])
    end

    def perform(unit, cmd)
      case cmd["kind"]
      when "defend" then ctx.emit(:defend, actor: unit["id"])
      when "flee" then Effects.attempt_flee(ctx, unit)
      when "item" then use_item(unit, ctx.item(cmd["item"]), cmd["target"])
      else
        ability = desperate(unit, ctx.ability(cmd["ability"]))
        ability = perfect(ability) if cmd["timing"] == "perfect"
        use_ability(unit, ability, cmd["target"])
      end
    end

    # A Perfect on the timing meter: every power in the move up by a quarter,
    # every chance to inflict a status up by 20 points. Marked on the move,
    # so the table sees it.
    PERFECT_POWER = 125
    PERFECT_CHANCE = 20

    def perfect(ability)
      effects = ability["effects"].map do |effect|
        effect = effect.dup
        effect["power"] = effect.fetch("power", 100) * PERFECT_POWER / 100 if %w[physical elemental heal drain].include?(effect["primitive"])
        effect["chance"] = [ effect.fetch("chance", 100) + PERFECT_CHANCE, 100 ].min if effect["primitive"] == "status"
        effect
      end
      ability.merge("effects" => effects, "perfect" => true)
    end

    # At the end of their rope, a character sometimes finds something more:
    # at a quarter of their HP or less, an attack has a chance to become
    # their desperation move instead. Once per battle, and free.
    DESPERATION_HP_PERCENT = 25
    DESPERATION_CHANCE = 30

    def desperate(unit, ability)
      move = unit["desperation"]
      return ability unless move && ability["id"] == "attack" && !unit["desperation_used"]
      return ability unless ctx.hp_percent(unit) <= DESPERATION_HP_PERCENT && ctx.rng.percent?(DESPERATION_CHANCE)

      unit["desperation_used"] = true
      special = ctx.ability(move)
      ctx.emit(:desperation, actor: unit["id"], ability: special["id"], name: special["name"])
      special.merge("cost" => {})
    end

    # An item works like an ability with no cost, and silence doesn't stop
    # it. It is used up when used, even if its target has gone.
    def use_item(unit, item, target_id)
      return ctx.emit(:action_failed, actor: unit["id"], item: item["id"], reason: "no_item") unless item["count"].positive?

      item["count"] -= 1
      targets = resolve_targets(unit, item, target_id)
      ctx.emit(:item_used, actor: unit["id"], item: item["id"], name: item["name"], targets: targets.map { |t| t["id"] }, left: item["count"])
      return ctx.emit(:miss, actor: unit["id"], item: item["id"], reason: "no_target") if targets.empty?

      apply_effects(unit, item, targets)
    end

    def use_ability(unit, ability, target_id)
      if ability["kind"] == "magic" && ctx.status?(unit, "silence")
        return ctx.emit(:action_failed, actor: unit["id"], ability: ability["id"], reason: "silenced")
      end

      cost = ctx.ability_cost(ability)
      if unit["mp"] < cost
        return ctx.emit(:action_failed, actor: unit["id"], ability: ability["id"], reason: "no_mp")
      end

      unit["mp"] -= cost
      if ability["target"] == "random_enemy"
        announce(unit, ability, [], cost)
        return random_hits(unit, ability)
      end

      targets = resolve_targets(unit, ability, target_id)
      announce(unit, ability, targets, cost)
      if targets.empty?
        return ctx.emit(:miss, actor: unit["id"], ability: ability["id"], reason: "no_target")
      end

      apply_effects(unit, ability, targets)
    end

    def apply_effects(unit, ability, targets)
      targets.each do |target|
        ability["effects"].each do |effect|
          hits(effect).times do
            break if ctx.over?
            break unless ctx.alive?(target) || effect["primitive"] == "revive"

            Effects.apply(ctx, unit, target, effect)
          end
        end
      end
    end

    def announce(unit, ability, targets, cost)
      type = ability["kind"] == "attack" ? :attack : :cast
      extra = ability["perfect"] ? { perfect: true } : {}
      ctx.emit(type, actor: unit["id"], ability: ability["id"], targets: targets.map { |t| t["id"] }, mp_cost: cost, **extra)
    end

    # random_enemy: every hit of every effect picks a fresh living opponent.
    def random_hits(unit, ability)
      ability["effects"].each do |effect|
        hits(effect).times do
          break if ctx.over?

          target = ctx.rng.pick(ctx.opponents(unit))
          break unless target

          Effects.apply(ctx, unit, target, effect)
        end
      end
    end

    def hits(effect)
      %w[physical elemental].include?(effect["primitive"]) ? effect.fetch("hits", 1) : 1
    end

    # Retargeting: a single target that is no longer valid is replaced — a
    # random living opponent for offence, the most wounded ally for support,
    # a random fallen ally for revival.
    def resolve_targets(unit, ability, target_id)
      revive = ctx.revives?(ability)
      chosen = target_id && ctx.find_unit(target_id)

      case ability["target"]
      when "self" then [ unit ]
      when "single_enemy"
        chosen = nil unless chosen && chosen["side"] != unit["side"] && ctx.alive?(chosen)
        [ chosen || ctx.rng.pick(ctx.opponents(unit)) ].compact
      when "single_ally"
        fallen = ctx.allies(unit, alive: false).reject { |a| ctx.alive?(a) }
        valid = chosen && chosen["side"] == unit["side"] && (revive ? !ctx.alive?(chosen) : ctx.alive?(chosen))
        return [ chosen ] if valid
        return [ ctx.rng.pick(fallen) ].compact if revive

        [ ctx.allies(unit).min_by { |a| [ ctx.hp_percent(a), a["hp"] ] } ]
      when "all_enemies" then ctx.opponents(unit)
      when "all_allies" then ctx.allies(unit, alive: !revive)
      end
    end

    def close_round(inputs)
      inputs.each { |id, cmd| ctx.unit(id)["last_command"] = cmd }
      ctx.units.each { |u| u["defending"] = false }
      state["inputs"] = {}
      ctx.emit(:round_end, round: state["round"])
      state["round"] += 1 unless ctx.over?
    end
  end
end
