# frozen_string_literal: true

require "json"

module Battle
  class Error < StandardError; end
  # Raised when an action is not legal against the current state. The state
  # passed in is never modified, so the caller can simply reject the action.
  class InvalidAction < Error; end

  # Closed vocabularies (§3.1). World authors compose from these; they never
  # extend them.
  PRIMITIVES = %w[physical elemental status heal drain buff debuff revive escape].freeze

  # Parameters each primitive takes, split into required and optional
  # (optional ones have defaults in Battle::Effects). String-valued params
  # are named in PRIMITIVE_STRING_PARAMS; everything else is an integer.
  PRIMITIVE_PARAMS = {
    "physical" => { required: [], optional: %w[power hits] },
    "elemental" => { required: %w[element power], optional: %w[hits] },
    "status" => { required: %w[kind], optional: %w[chance duration] },
    "heal" => { required: %w[power], optional: [] },
    "drain" => { required: %w[power], optional: [] },
    "buff" => { required: %w[stat amount], optional: %w[duration] },
    "debuff" => { required: %w[stat amount], optional: %w[duration] },
    "revive" => { required: [], optional: %w[fraction] },
    "escape" => { required: [], optional: [] }
  }.freeze
  PRIMITIVE_STRING_PARAMS = %w[element kind stat].freeze
  TARGETINGS = %w[self single_ally single_enemy all_allies all_enemies random_enemy].freeze
  ELEMENTS = %w[fire ice bolt water wind earth holy dark].freeze
  AFFINITIES = %w[weak resist immune absorb].freeze
  STATUSES = %w[poison sleep paralyze silence blind haste slow].freeze
  ABILITY_KINDS = %w[attack skill magic].freeze
  COMMAND_KINDS = %w[ability defend flee].freeze
  SIDES = %w[party enemy].freeze

  # Statuses that stop a unit from taking its turn (and from being asked
  # for input).
  DISABLING_STATUSES = %w[sleep paralyze].freeze

  ATTACK = {
    "id" => "attack",
    "name" => "Attack",
    "kind" => "attack",
    "target" => "single_enemy",
    "cost" => { "mp" => 0 },
    "effects" => [ { "primitive" => "physical", "power" => 100, "hits" => 1 } ]
  }.freeze

  # Battle state is a plain, JSON-shaped hash with string keys. It is what the
  # `battles.state` column stores and what the resolver folds over.
  module State
    VERSION = 1

    module_function

    # Deep-copy and canonicalise: string keys, no symbols. Anything that
    # survives this survives a round trip through a JSON column.
    def normalize(obj)
      JSON.parse(JSON.generate(obj))
    end

    # Build an initial battle state.
    #
    # party:     [{ id:, name:, stats:, abilities: [...], elements: {}, status_immune: [] , hp:, mp: }]
    # enemies:   same shape plus ai: [rules], rewards: {}, and optional count: n
    # abilities: { "fire" => { name:, kind:, target:, cost: { mp: }, effects: [...] } }
    def build(seed:, party:, enemies:, abilities: {}, escapable: true)
      library = normalize(abilities)
      library["attack"] ||= normalize(ATTACK)
      library.each do |id, ability|
        ability["id"] = id
        validate_ability!(ability)
      end

      units = normalize(party).map { |spec| unit(spec, "party") }
      units += expand_enemies(normalize(enemies)).map { |spec| unit(spec, "enemy") }

      duplicate = units.map { |u| u["id"] }.tally.find { |_, n| n > 1 }
      raise ArgumentError, "duplicate unit id #{duplicate.first}" if duplicate

      units.each do |u|
        missing = u["abilities"] - library.keys
        raise ArgumentError, "#{u['id']} knows unknown abilities: #{missing.join(', ')}" if missing.any?
      end

      {
        "version" => VERSION,
        "seed" => Integer(seed),
        "rng" => Rng.seed_state(seed),
        "round" => 1,
        "status" => "input",
        "escapable" => escapable ? true : false,
        "abilities" => library,
        "units" => units,
        "inputs" => {}
      }
    end

    def unit(spec, side)
      id = spec.fetch("id") { raise ArgumentError, "unit needs an id" }.to_s
      stats = spec.fetch("stats") { raise ArgumentError, "#{id} needs stats" }
      missing = Stats::NAMES - stats.keys
      raise ArgumentError, "#{id} is missing stats: #{missing.join(', ')}" if missing.any?

      elements = spec.fetch("elements", {})
      bad = elements.reject { |el, aff| ELEMENTS.include?(el) && AFFINITIES.include?(aff) }
      raise ArgumentError, "#{id} has invalid elements #{bad}" if bad.any?

      {
        "id" => id,
        "name" => spec.fetch("name", id),
        "side" => side,
        "stats" => stats,
        "hp" => spec.fetch("hp", stats["max_hp"]).clamp(0, stats["max_hp"]),
        "mp" => spec.fetch("mp", stats["max_mp"]).clamp(0, stats["max_mp"]),
        "statuses" => [],
        "buffs" => [],
        "abilities" => ([ "attack" ] + spec.fetch("abilities", [])).uniq,
        "elements" => elements,
        "status_immune" => spec.fetch("status_immune", []),
        "ai" => spec.fetch("ai", []),
        "rewards" => spec.fetch("rewards", {}),
        "image" => spec["image"],
        "defending" => false,
        "last_command" => nil
      }
    end

    # { id: "goblin", name: "Goblin", count: 3 } -> Goblin A, Goblin B, Goblin C
    def expand_enemies(specs)
      expanded = specs.flat_map { |spec| Array.new(spec.fetch("count", 1)) { spec.except("count") } }
      counts = expanded.map { |s| s["id"] }.tally
      seen = Hash.new(0)
      expanded.map do |spec|
        next spec if counts[spec["id"]] == 1

        letter = ("A".ord + seen[spec["id"]]).chr
        seen[spec["id"]] += 1
        spec.merge("id" => "#{spec['id']}_#{letter.downcase}", "name" => "#{spec.fetch('name', spec['id'])} #{letter}")
      end
    end

    # --- read-only queries for the UI -------------------------------------
    # Rules live here so views never re-derive them (§12). The resolver
    # uses the same functions.

    # Party members who can act this round (alive, not asleep or paralysed).
    def able_to_act(state)
      state["units"].select do |u|
        u["side"] == "party" && u["hp"].positive? &&
          u["statuses"].none? { |s| DISABLING_STATUSES.include?(s["kind"]) }
      end.map { |u| u["id"] }
    end

    # Party members the round is still waiting on.
    def awaiting_input(state)
      return [] unless state["status"] == "input"

      able_to_act(state) - state["inputs"].keys
    end

    def ability_cost(ability)
      ability.fetch("cost", {}).fetch("mp", 0)
    end

    # Can this unit pay for and use the ability right now?
    def usable?(unit, ability)
      return false unless unit["abilities"].include?(ability["id"])
      return false if ability["kind"] == "magic" && unit["statuses"].any? { |s| s["kind"] == "silence" }

      unit["mp"] >= ability_cost(ability)
    end

    def revives?(ability)
      ability["effects"].any? { |e| e["primitive"] == "revive" }
    end

    # Unit ids a player may pick as the target, or nil when the ability's
    # targeting needs no choice (self, all, random).
    def target_options(state, unit, ability)
      living = ->(u) { u["hp"].positive? }
      case ability["target"]
      when "single_enemy"
        state["units"].select { |u| u["side"] != unit["side"] && living.(u) }.map { |u| u["id"] }
      when "single_ally"
        allies = state["units"].select { |u| u["side"] == unit["side"] }
        allies.select { |u| revives?(ability) ? !living.(u) : living.(u) }.map { |u| u["id"] }
      end
    end

    def validate_ability!(ability)
      id = ability["id"]
      raise ArgumentError, "#{id}: unknown kind #{ability['kind']}" unless ABILITY_KINDS.include?(ability.fetch("kind", "skill"))
      raise ArgumentError, "#{id}: unknown targeting #{ability['target']}" unless TARGETINGS.include?(ability["target"])

      effects = ability.fetch("effects", [])
      raise ArgumentError, "#{id}: needs at least one effect" if effects.empty?

      effects.each do |effect|
        primitive = effect["primitive"]
        raise ArgumentError, "#{id}: unknown primitive #{primitive}" unless PRIMITIVES.include?(primitive)

        params = PRIMITIVE_PARAMS.fetch(primitive)
        missing = params[:required] - effect.keys
        raise ArgumentError, "#{id}: #{primitive} needs #{missing.join(', ')}" if missing.any?

        unknown = effect.keys - [ "primitive" ] - params[:required] - params[:optional]
        raise ArgumentError, "#{id}: #{primitive} does not take #{unknown.join(', ')}" if unknown.any?

        (effect.keys - [ "primitive" ] - PRIMITIVE_STRING_PARAMS).each do |param|
          raise ArgumentError, "#{id}: #{primitive} #{param} must be an integer" unless effect[param].is_a?(Integer)
        end

        case primitive
        when "elemental"
          raise ArgumentError, "#{id}: unknown element #{effect['element']}" unless ELEMENTS.include?(effect["element"])
        when "status"
          raise ArgumentError, "#{id}: unknown status #{effect['kind']}" unless STATUSES.include?(effect["kind"])
        when "buff", "debuff"
          raise ArgumentError, "#{id}: cannot modify #{effect['stat']}" unless Stats::MODIFIABLE.include?(effect["stat"])
        end
      end
    end
  end
end
