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
  #
  # Events are hashes with a "type" (Context#emit), the only contract with
  # the view (§12): every one that changes HP carries the resulting "hp", so
  # the view never computes an outcome. BattleLogHelper#battle_log_line
  # writes a line for each, and its spec checks every type the property
  # battles emit.
  class Resolver
    GM_OPS = %w[auto execute_round set_hp set_mp add_status remove_status end_battle add_unit dismiss rule].freeze
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

    # Custom actions the GM hasn't ruled on yet.
    def unruled
      state["inputs"].select { |_, cmd| cmd["kind"] == "custom" && !cmd["ruling"] }.keys
    end

    # Everyone has chosen and the GM has ruled on every idea: run the round.
    def ready?
      missing_inputs.empty? && unruled.empty?
    end

    def command(action)
      unit = ctx.unit(action["actor"])
      raise InvalidAction, "#{unit['id']} is not a party member" unless unit["side"] == "party"
      raise InvalidAction, "#{unit['id']} cannot act" unless awaiting.include?(unit["id"])

      cmd = validate_command(unit, action.fetch("command") { raise InvalidAction, "command missing" })
      state["inputs"][unit["id"]] = cmd
      ctx.emit(:command_accepted, actor: unit["id"])
      run_round if ready?
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
      return validate_custom(cmd) if kind == "custom"

      ability = ctx.ability(cmd.fetch("ability", "attack"))
      raise InvalidAction, "#{unit['id']} does not know #{ability['id']}" unless unit["abilities"].include?(ability["id"])
      raise InvalidAction, "#{unit['id']} is silenced" if ability["kind"] == "magic" && ctx.status?(unit, "silence")
      raise InvalidAction, "#{unit['id']} lacks MP for #{ability['id']}" if unit["mp"] < ctx.ability_cost(ability)
      raise InvalidAction, "#{unit['id']} lacks the HP for #{ability['id']}" unless ctx.usable?(unit, ability)

      target = cmd["target"]
      validate_target(unit, ability, target) if target
      command = { "kind" => "ability", "ability" => ability["id"], "target" => target }
      # The timing meter: stopped on the mark, the move lands harder.
      cmd["timing"] == "perfect" ? command.merge("timing" => "perfect") : command
    end

    # "Try something": the player's idea in words, for the GM to rule on.
    CUSTOM_TEXT_LIMIT = 200

    def validate_custom(cmd)
      text = cmd["text"].to_s.strip
      raise InvalidAction, "say what you try" if text.empty?
      raise InvalidAction, "keep it under #{CUSTOM_TEXT_LIMIT} characters" if text.length > CUSTOM_TEXT_LIMIT

      target = ctx.find_unit(cmd["target"].to_s) ? cmd["target"].to_s : nil
      { "kind" => "custom", "text" => text, "target" => target }
    end

    def validate_item(unit, cmd)
      item = ctx.item(cmd["item"])
      raise InvalidAction, "no #{item['name']} left" unless State.items_left(state, item["id"], except: unit["id"]).positive?

      target = cmd["target"]
      validate_target(unit, item, target) if target
      { "kind" => "item", "item" => item["id"], "target" => target }
    end

    # The one rule (State.target_problem), with its reason as the error.
    def validate_target(unit, ability, target_id)
      problem = State.target_problem(unit, ability, ctx.unit(target_id))
      raise InvalidAction, "#{target_id} #{problem}" if problem
    end

    def default_command(unit)
      last = unit["last_command"]&.except("timing") # a Perfect is earned each round
      return last if last && still_valid?(unit, last)

      { "kind" => "ability", "ability" => "attack", "target" => nil }
    end

    def still_valid?(unit, cmd)
      case cmd["kind"]
      when "custom" then false # an idea is for its moment
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
      run_round if ready?
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
      raise InvalidAction, "#{kind} comes from a move, not on its own" if PRIMITIVE_STATUSES.include?(kind)
      raise InvalidAction, "#{unit['id']} is down" unless ctx.alive?(unit)

      gm_event(action, unit: unit["id"], status: kind)
      ctx.add_status(unit, kind, Integer(action.fetch("turns", 3)))
      state["inputs"].delete(unit["id"]) if NO_INPUT_STATUSES.include?(kind)
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
          State.validate_ability!(ability, ctx.type_list)
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
        unit = State.unit(spec.merge("id" => id, "name" => name), side, ctx.type_list)
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

    # The GM rules on a player's idea ("Try something"): which stat, how hard,
    # what success does (effects from the closed primitive set, aimed like
    # an ability), and what's said either way. It plays out on the unit's
    # turn (#try_something).
    #   { op: "rule", unit:, stat:, difficulty:, aim: "single_enemy", effects: [...],
    #     success: "The brazier tips over!", failure: "It's heavier than it looks.",
    #     skill: "Athletics", bonus: 15 }   # optional: a skill check, and the job's bonus
    RULING_AIMS = %w[single_enemy all_enemies single_ally all_allies self].freeze

    def gm_rule(action)
      unit = ctx.unit(action["unit"])
      cmd = state["inputs"][unit["id"]]
      raise InvalidAction, "#{unit['name']} isn't trying anything" unless cmd && cmd["kind"] == "custom"
      raise InvalidAction, "unknown stat #{action['stat'].inspect}" unless Stats::Check::STATS.include?(action["stat"])
      raise InvalidAction, "unknown difficulty #{action['difficulty'].inspect}" unless Stats::Check::DIFFICULTIES.key?(action["difficulty"])
      bonus = action.fetch("bonus", 0)
      raise InvalidAction, "bonus must be 0 to #{Stats::Check::MAX_BONUS}" unless bonus.is_a?(Integer) && bonus.between?(0, Stats::Check::MAX_BONUS)

      aim = action.fetch("aim", "single_enemy")
      raise InvalidAction, "unknown aim #{aim.inspect}" unless RULING_AIMS.include?(aim)

      effects = Array(action["effects"])
      begin
        State.validate_ability!({ "id" => "ruling", "kind" => "skill", "target" => aim, "effects" => effects }, ctx.type_list) if effects.any?
      rescue ArgumentError => e
        raise InvalidAction, e.message
      end

      ruling = { "stat" => action["stat"], "difficulty" => action["difficulty"], "aim" => aim, "effects" => effects,
                 "success" => action["success"].to_s.strip, "failure" => action["failure"].to_s.strip }
      # A skill check: the world's skill, on its stat, with the job's bonus.
      ruling.merge!("skill" => action["skill"].to_s, "bonus" => bonus) unless action["skill"].to_s.strip.empty?
      cmd["ruling"] = ruling
      gm_event(action, unit: unit["id"], stat: ruling["stat"], difficulty: ruling["difficulty"])
      run_round if ready?
    end

    # A player's idea on their turn: the d100 against their stat (the same
    # odds as a check at the table), then what the GM said success does. An
    # idea nobody ruled on (the timer ran out) is an Attack instead.
    def try_something(unit, cmd)
      # Whoever it was aimed at may have left the field since.
      cmd = cmd.merge("target" => nil) if cmd["target"] && ctx.find_unit(cmd["target"])&.dig("gone")
      ctx.emit(:custom_action, actor: unit["id"], text: cmd["text"], target: cmd["target"])
      ruling = cmd["ruling"]
      unless ruling
        ctx.emit(:custom_unruled, actor: unit["id"])
        return use_ability(unit, own(unit, ctx.ability("attack")), cmd["target"])
      end

      bonuses = ruling.fetch("bonus", 0).positive? ? [ { "label" => ruling["skill"] || "Bonus", "amount" => ruling["bonus"] } ] : []
      result = Stats::Check.roll(stat_value: ctx.stat(unit, ruling["stat"]), stat: ruling["stat"], level: unit.fetch("level", 5),
                                 difficulty: ruling["difficulty"], rng: ctx.rng, bonuses: bonuses)
      success = result["success"]
      line = success ? ruling["success"] : ruling["failure"]
      ctx.emit(:custom_roll, actor: unit["id"], success: success, stat: ruling["stat"], difficulty: ruling["difficulty"], line: line,
                             **result.slice("roll", "modifiers", "total", "needed").transform_keys(&:to_sym), **ruling.slice("skill").transform_keys(&:to_sym))
      return unless success && ruling["effects"].any?

      idea = { "id" => "custom", "name" => cmd["text"], "kind" => "skill", "target" => ruling["aim"], "effects" => ruling["effects"] }
      targets = resolve_targets(unit, idea, cmd["target"])
      apply_effects(unit, idea, targets) if targets.any?
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
      hasted = order.select { |id| ctx.status?(ctx.unit(id), "haste") }
      all_out = false
      order.each do |id|
        break if ctx.over?

        mark = ctx.events.size
        take_turn(ctx.unit(id), inputs[id])
        ctx.check_end
        next unless state.dig("rules", "one_more") && !ctx.over?

        one_more(ctx.unit(id), inputs[id], mark)
        all_out ||= all_out_attack(ctx.unit(id), mark) unless ctx.over?
      end
      # Haste: whoever was quick when the round began has a second go at
      # its end, the same move again.
      hasted.each do |id|
        break if ctx.over?

        quick_turn(ctx.unit(id), inputs[id])
        ctx.check_end
      end

      close_round(inputs)
    end

    # Speed order: agi plus up to a quarter of agi at random. Ties go to
    # the unit listed first. In the first round, First Strike goes before
    # everyone (the roll is still drawn, so the stream doesn't change).
    def turn_order
      ctx.units.each_with_index.filter_map do |u, index|
        next unless ctx.alive?(u)

        agi = ctx.stat(u, "agi")
        early = state["round"] == 1 && Array(u["passives"]).include?("first_strike") ? 0 : 1
        [ early, -(agi + ctx.rng.int(agi / 4 + 1)), index, u["id"] ]
      end.sort.map(&:last)
    end

    # A Jump comes down: a blow at the target it left for (or, if that one's
    # gone, anyone in reach), whatever else was going on. status: the away
    # it's coming back from; battles from before Away were airborne.
    def land(unit, status = nil)
      unless status
        status = unit["statuses"].find { |s| s["kind"] == "airborne" }
        ctx.remove_status(unit, "airborne", reason: "landed")
      end
      target = ctx.find_unit(status["target"].to_s)
      target = nil unless target && target["side"] != unit["side"] && ctx.alive?(target) && !ctx.out_of_reach?(target)
      target ||= ctx.rng.pick(ctx.opponents(unit))
      ctx.emit(:land, actor: unit["id"], target: target&.dig("id"))
      blow = { "primitive" => "physical", "power" => status.fetch("power", 200) }.merge(status.slice("type", "basis"))
      Effects.apply(ctx, unit, target, blow) if target
    end

    # Someone away counts down their turns; on the last they come back. A
    # blow on the way back (a Jump) is their turn, and so is being sent
    # away; someone who left quietly of their own accord (Hide) acts.
    # Returns true when the turn is spent.
    def come_back(unit)
      status = unit["statuses"].find { |s| s["kind"] == "away" }
      status["left"] = status.fetch("left", status["turns"]) - 1 # a GM's or a status move's away counts its turns too
      if status["left"].positive?
        ctx.emit(:turn_skipped, unit: unit["id"], reason: "away")
        return true
      end

      unit["statuses"].delete(status)
      if status.fetch("power", 0).positive?
        land(unit, status)
        return true
      end
      ctx.emit(:back, unit: unit["id"])
      !status["self"]
    end

    def take_turn(unit, cmd)
      return unless ctx.alive?(unit) # KO'd earlier this round: no turn at all

      ctx.emit(:turn_start, unit: unit["id"])
      # What the unit carried into its turn: only that counts this turn down.
      # A buff it gives itself now lasts its full length (War Cry for 3 is
      # three buffed turns, not two).
      held = unit["buffs"] + unit["statuses"]
      blocking = DISABLING_STATUSES.find { |kind| ctx.status?(unit, kind) }
      if ctx.status?(unit, "airborne")
        land(unit)
      elsif ctx.status?(unit, "away") && come_back(unit)
        nil
      elsif blocking
        ctx.emit(:turn_skipped, unit: unit["id"], reason: blocking)
      elsif ctx.status?(unit, "charging")
        release(unit)
      elsif ctx.status?(unit, "confuse")
        run_amok(unit)
      elsif ctx.status?(unit, "berserk")
        use_ability(unit, own(unit, ctx.ability("attack")), nil)
      elsif unit["side"] == "enemy" || unit["guest"]
        ability, target, rule = AI.choose(ctx, unit)
        AI.fire(ctx, unit, rule)
        use_ability(unit, own(unit, ability), target)
      elsif cmd.nil?
        ctx.emit(:turn_skipped, unit: unit["id"], reason: "no_command")
      else
        perform(unit, cmd)
      end

      Effects.upkeep(ctx, unit, held: held) if ctx.alive?(unit) && !ctx.over?
      ctx.emit(:turn_end, unit: unit["id"])
      count_down_summon(unit) unless ctx.over?
    end

    # A hasted unit's second go: the same move again, and nothing else of a
    # turn (no upkeep, no countdowns). Only a plain move repeats: not an item
    # (that's the party's to spend), a flight, an idea for the GM, a wind-up,
    # a leap or a summons.
    SINGLE_GO = %w[jump away summon escape].freeze

    def quick_turn(unit, cmd)
      return unless ctx.status?(unit, "haste")

      extra_go(unit, cmd)
    end

    # One More (a world's rule, Battle::RULES): a blow on its turn that found
    # a weakness or landed a critical hit knocks the one it hit down (they
    # lose their next turn), and whoever struck goes again at once, the same
    # move (as haste's second go, #extra_go). Once a turn: the other go
    # knocks down too, but doesn't go again. Someone already down isn't
    # knocked down twice, and gives nobody another go.
    def one_more(unit, cmd, mark)
      downed = knock_down(unit, ctx.events[mark..])
      return if downed.empty? || !ctx.alive?(unit)

      # The same move that found the weakness (an enemy's too, not a fresh pick from its script).
      used = ctx.events[mark..].reverse.find { |e| %w[attack cast].include?(e["type"]) && e["actor"] == unit["id"] }&.dig("ability")
      cmd = next_mark(unit, cmd)
      ctx.emit(:one_more, actor: unit["id"], downed: downed, **(cmd && cmd["target"] ? { target: cmd["target"] } : {}))
      mark = ctx.events.size
      extra_go(unit, cmd, reason: "one_more", repeat: used)
      ctx.check_end
      knock_down(unit, ctx.events[mark..]) unless ctx.over?
    end

    # The other go finds its own mark: a move at one enemy goes for whoever
    # is still standing and weakest to it (first in line on a tie), since
    # the one it knocked down is down. Where everyone is down, or the move
    # isn't at one enemy, it's the same command.
    def next_mark(unit, cmd)
      return cmd unless cmd && cmd["kind"] == "ability" && cmd["target"]

      ability = ctx.ability(cmd["ability"])
      return cmd unless ability && ability["target"] == "single_enemy"

      standing = ctx.opponents(unit).reject { |foe| ctx.status?(foe, "down") }
      return cmd if standing.empty? || standing.any? { |foe| foe["id"] == cmd["target"] }

      damage = own(unit, ability)["effects"].find { |e| e.key?("type") }
      type = damage && Effects.type_of(ctx, damage)
      score = ->(foe) { (percent = Types.effectiveness(type, foe, ctx.types)) == :absorb ? -1 : percent }
      best = standing.each_with_index.max_by { |foe, i| [ score.(foe), -i ] }.first
      cmd.merge("target" => best["id"])
    end

    # All-Out Attack (One More): once the party's blows have every enemy
    # still standing knocked down, everyone in the party who can act piles
    # in at once, each with an Attack on every enemy, and the enemies get
    # back up. Once a round, on the party's side only.
    def all_out_attack(unit, mark)
      return false unless unit["side"] == "party"

      foes = ctx.opponents(unit)
      return false if foes.empty? || !foes.all? { |foe| ctx.status?(foe, "down") }
      return false unless ctx.events[mark..].any? { |e| e["type"] == "one_more" }

      crew = ctx.allies(unit).reject { |ally| (DISABLING_STATUSES + %w[airborne away charging confuse]).any? { |kind| ctx.status?(ally, kind) } }
      return false if crew.empty?

      ctx.emit(:all_out, actor: unit["id"], units: crew.map { |ally| ally["id"] }, targets: foes.map { |foe| foe["id"] })
      crew.each do |ally|
        break if ctx.over?

        apply_effects(ally, own(ally, ctx.ability("attack")), ctx.opponents(ally)) if ctx.alive?(ally)
        ctx.check_end
      end
      ctx.opponents(unit).each { |foe| ctx.remove_status(foe, "down", reason: "all_out") } unless ctx.over?
      true
    end

    def knock_down(unit, events)
      events.filter_map do |event|
        next unless event["type"] == "damage" && event["actor"] == unit["id"] && (event["crit"] || event["effectiveness"].to_i > 100)

        target = ctx.find_unit(event["target"].to_s)
        next unless target && target["side"] != unit["side"] && ctx.alive?(target) && !ctx.status?(target, "down")

        ctx.add_status(target, "down", 1)
        target["id"]
      end
    end

    # Another go, the same move again, and nothing else of a turn (no upkeep,
    # no countdowns): haste's second go, and One More.
    # repeat: the move to go again with, for a unit the AI plays (One More).
    def extra_go(unit, cmd, reason: nil, repeat: nil)
      return unless ctx.alive?(unit)
      return if (DISABLING_STATUSES + %w[airborne away charging confuse]).any? { |kind| ctx.status?(unit, kind) }

      ai = unit["side"] == "enemy" || unit["guest"]
      ability = if ctx.status?(unit, "berserk") then ctx.ability("attack")
      elsif ai && repeat && ctx.state["abilities"][repeat] then (chosen = [ ctx.ability(repeat), nil ]).first
      elsif ai then (chosen = AI.choose(ctx, unit)).first
      elsif cmd && cmd["kind"] == "ability" then ctx.ability(cmd["ability"])
      end
      return unless ability && ability.fetch("charge", 0).zero? && ability["effects"].none? { |e| SINGLE_GO.include?(e["primitive"]) }

      ctx.emit(:turn_start, unit: unit["id"], quick: true, **(reason ? { reason: reason } : {}))
      if chosen
        AI.fire(ctx, unit, chosen[2])
        use_ability(unit, own(unit, ability), chosen[1])
      elsif ctx.status?(unit, "berserk") then use_ability(unit, own(unit, ability), nil)
      else perform(unit, cmd)
      end
      ctx.emit(:turn_end, unit: unit["id"], quick: true)
    end

    # Confused: an Attack at anyone in reach but itself, friend or foe.
    def run_amok(unit)
      pool = ctx.units.select { |u| u != unit && ctx.alive?(u) && !ctx.out_of_reach?(u) }
      target = ctx.rng.pick(pool)
      ctx.emit(:confused, actor: unit["id"], target: target&.dig("id"))
      return unless target

      attack = own(unit, ctx.ability("attack"))
      announce(unit, attack, [ target ], 0)
      apply_effects(unit, attack, [ target ])
    end

    def perform(unit, cmd)
      case cmd["kind"]
      when "defend" then ctx.emit(:defend, actor: unit["id"])
      when "flee" then Effects.attempt_flee(ctx, unit)
      when "item" then use_item(unit, ctx.item(cmd["item"]), cmd["target"])
      when "custom" then try_something(unit, cmd)
      else
        ability = own(unit, desperate(unit, ctx.ability(cmd["ability"])))
        ability = perfect(ability) if cmd["timing"] == "perfect"
        use_ability(unit, ability, cmd["target"])
      end
    end

    # What a character's jobs make of a move (State.job_parts): Attack and
    # the job's own command strike with the job's type, and mastery and the
    # active job scale its power (Stats::Mastery). A mastered move used
    # outside its job brings that job's stats with it.
    POWERED = %w[physical elemental heal drain jump away shield sap summon].freeze
    # What an effect's power is when it doesn't say.
    DEFAULT_POWER = { "jump" => 200, "away" => 0 }.freeze

    def power_of(effect)
      effect.fetch("power") { DEFAULT_POWER.fetch(effect["primitive"], 100) }
    end

    # An imbued Attack takes the imbued type over the job's.
    def own(unit, ability)
      imbued = unit["statuses"].find { |s| s["kind"] == "imbued" }&.dig("type")
      attack_type = ability["id"] == "attack" && imbued ? imbued : unit["attack_type"]
      typed = attack_type && (ability["id"] == "attack" || ability["id"] == unit["signature"])
      mastery = unit.dig("mastery", ability["id"])
      return ability unless typed || mastery

      effects = ability["effects"].map do |effect|
        effect = effect.dup
        effect["type"] ||= attack_type if typed && %w[physical jump].include?(effect["primitive"])
        if mastery && POWERED.include?(effect["primitive"])
          effect["power"] = power_of(effect) * mastery["power"] / 100
          effect["basis"] = mastery["stats"] if mastery["stats"]
        end
        effect
      end
      ability.merge("effects" => effects)
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

    # A move that takes turns to go off: the user winds it up (charging,
    # no commands) and it goes off on the turn the charge runs out, paid for
    # then (#release). Knocked out, the charge is lost with every status.
    def wind_up(unit, ability, target_id)
      unit["statuses"] << { "kind" => "charging", "turns" => ability["charge"], "left" => ability["charge"],
                            "ability" => ability, "target" => target_id }
      ctx.emit(:charging, actor: unit["id"], ability: ability["id"], turns: ability["charge"])
    end

    # Counts the charge down; on the last turn the move goes off.
    def release(unit)
      status = unit["statuses"].find { |s| s["kind"] == "charging" }
      status["left"] = status.fetch("left", status["turns"]) - 1
      return ctx.emit(:turn_skipped, unit: unit["id"], reason: "charging") if status["left"].positive?

      unit["statuses"].delete(status)
      ability = status["ability"] || ctx.ability("attack")
      use_ability(unit, ability.merge("released" => true), status["target"])
    end

    # Charged: the next move that deals or restores HP is twice as strong,
    # and the charge is spent on it.
    CHARGE_POWER = 200

    def charged(unit, ability)
      return ability unless ctx.status?(unit, "charged") && ability["effects"].any? { |e| POWERED.include?(e["primitive"]) }

      ctx.remove_status(unit, "charged", reason: "spent")
      effects = ability["effects"].map do |effect|
        POWERED.include?(effect["primitive"]) ? effect.merge("power" => power_of(effect) * CHARGE_POWER / 100) : effect
      end
      ability.merge("effects" => effects)
    end

    # An item works like an ability with no cost, and silence doesn't stop
    # it. It is used up when used, even if its target has gone.
    def use_item(unit, item, target_id)
      return ctx.emit(:action_failed, actor: unit["id"], item: item["id"], reason: "no_item") unless item["count"].positive?

      item["count"] -= 1
      targets = resolve_targets(unit, item, target_id)
      ctx.emit(:item_used, actor: unit["id"], item: item["id"], name: item["name"], targets: targets.map { |t| t["id"] }, left: item["count"])
      return ctx.emit(:miss, actor: unit["id"], item: item["id"], reason: "no_target") if targets.empty?

      apply_effects(unit, item, targets, item: true)
    end

    def use_ability(unit, ability, target_id)
      if ability["kind"] == "magic" && ctx.status?(unit, "silence")
        return ctx.emit(:action_failed, actor: unit["id"], ability: ability["id"], reason: "silenced")
      end

      cost = ctx.ability_cost(ability)
      if unit["mp"] < cost
        return ctx.emit(:action_failed, actor: unit["id"], ability: ability["id"], reason: "no_mp")
      end
      blood = State.hp_cost(unit, ability)
      if blood.positive? && unit["hp"] <= blood
        return ctx.emit(:action_failed, actor: unit["id"], ability: ability["id"], reason: "no_hp")
      end
      return wind_up(unit, ability, target_id) if ability.fetch("charge", 0).positive? && !ability["released"]

      unit["mp"] -= cost
      if blood.positive?
        unit["hp"] -= blood
        ctx.emit(:hp_paid, actor: unit["id"], amount: blood, hp: unit["hp"])
      end
      ability = charged(unit, ability)
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

    # Summoned creatures act as soon as the move that called them is done.
    def arrive
      while (creature = ctx.arrivals.shift)
        break if ctx.over?

        ability, target, rule = AI.choose(ctx, creature)
        AI.fire(ctx, creature, rule)
        use_ability(creature, own(creature, ability), target)
        ctx.check_end
        count_down_summon(creature)
      end
    end

    # A summoned creature leaves once its turns are up (or it's down).
    def count_down_summon(unit)
      return unless unit["summoned"] && !unit["gone"]

      unit["summoned"]["left"] -= 1
      return if unit["summoned"]["left"].positive? && ctx.alive?(unit)

      unit["gone"] = true
      unit["statuses"] = []
      unit["buffs"] = []
      ctx.emit(:unit_left, unit: unit["id"], name: unit["name"], summoned: true)
      ctx.check_end
    end

    # item: an item's effects work the same whoever uses them (Effects#heal).
    def apply_effects(unit, ability, targets, item: false)
      targets.each do |target|
        ability["effects"].each do |effect|
          effect = effect.merge("item" => true) if item
          hits(effect).times do
            break if ctx.over?
            break unless ctx.alive?(target) || effect["primitive"] == "revive"

            Effects.apply(ctx, unit, target, effect)
          end
        end
      end
      arrive
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
      arrive
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
        chosen = nil unless chosen && State.valid_target?(unit, ability, chosen)
        [ covered(chosen || ctx.rng.pick(ctx.opponents(unit))) ].compact
      when "single_ally"
        fallen = ctx.allies(unit, alive: false).reject { |a| ctx.alive?(a) }
        return [ chosen ] if chosen && State.valid_target?(unit, ability, chosen)
        return [ ctx.rng.pick(fallen) ].compact if revive

        [ ctx.allies(unit).min_by { |a| [ ctx.hp_percent(a), a["hp"] ] } ]
      when "all_enemies" then ctx.opponents(unit)
      when "all_allies" then ctx.allies(unit, alive: !revive)
      end
    end

    # Cover: a unit meant for this blow has an ally standing in front of it.
    def covered(target)
      return target unless target

      guard = ctx.allies(target).find { |a| a != target && AGGRO_STATUSES.any? { |k| ctx.status?(a, k) } && !ctx.out_of_reach?(a) }
      return target unless guard

      ctx.emit(:covered, unit: guard["id"], for: target["id"])
      guard
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
