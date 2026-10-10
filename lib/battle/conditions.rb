# frozen_string_literal: true

module Battle
  # The field a fight is on, and what it does: stages in order (ankle-deep,
  # waist-deep, chest-deep), each with its conditions, and how many rounds
  # it lasts before the next comes on its own (the water rising). The
  # GM can bring the next on, or any, at once (Resolver#gm_field).
  #
  #   { "stages" => [ { "name" => "Ankle-deep", "line" => "…", "rounds" => 3,
  #                     "conditions" => [ { "kind" => "weaken", "type" => "fire", "amount" => 50 } ] }, … ],
  #     "stage" => 0, "since" => 1 }
  #
  # The conditions are a closed set, like the primitives (§3.1):
  #   weaken(type, amount)  moves of the type do amount% less, whoever's they are
  #   slow(amount)          everyone's Agi is amount% lower
  #   conduct(type)         a single-target move of the type hits everyone on its target's side
  #   drown(amount, spares) everyone loses amount% of their max HP as the round ends,
  #                         but those of the type it spares (what lives in the water)
  #   dark(amount)          blows find their mark amount points less often
  module Conditions
    KINDS = {
      "weaken" => { required: %w[type amount], optional: [] },
      "slow" => { required: %w[amount], optional: [] },
      "conduct" => { required: %w[type], optional: [] },
      "drown" => { required: %w[amount], optional: %w[spares] },
      "dark" => { required: %w[amount], optional: [] }
    }.freeze
    TYPED = %w[type spares].freeze
    MAX_STAGES = 6
    MAX_ROUNDS = 20
    MAX_DROWN = 25
    NAME_LIMIT = 40
    LINE_LIMIT = 200

    module_function

    # A field as a book or a room writes it: { "stages" => [...] }, or just
    # the stages. Returns the field a battle starts on, or nil for none.
    def build(field, known)
      stages = field.is_a?(Hash) ? field["stages"] : field
      return if stages.nil? || stages.empty?
      raise ArgumentError, "a field has 1 to #{MAX_STAGES} stages" unless stages.is_a?(Array) && stages.size <= MAX_STAGES

      { "stages" => stages.each_with_index.map { |stage, i| stage(stage, i, known) }, "stage" => 0, "since" => 1 }
    end

    def stage(stage, index, known)
      label = "field stage #{index + 1}"
      raise ArgumentError, "#{label} isn't a stage" unless stage.is_a?(Hash)

      name = stage["name"].to_s.strip
      raise ArgumentError, "#{label} needs a name of #{NAME_LIMIT} letters or fewer" if name.empty? || name.length > NAME_LIMIT
      line = stage["line"].to_s.strip
      raise ArgumentError, "#{label}'s line is too long" if line.length > LINE_LIMIT
      rounds = stage["rounds"]
      raise ArgumentError, "#{label} lasts 1 to #{MAX_ROUNDS} rounds, or until moved on" unless rounds.nil? || (rounds.is_a?(Integer) && rounds.between?(1, MAX_ROUNDS))

      conditions = Array(stage["conditions"]).map { |condition| condition(condition, label, known) }
      { "name" => name, "conditions" => conditions }.merge(line.empty? ? {} : { "line" => line }).merge(rounds ? { "rounds" => rounds } : {})
    end

    def condition(condition, label, known)
      kind = condition["kind"] if condition.is_a?(Hash)
      spec = KINDS[kind] or raise ArgumentError, "#{label} has an unknown condition #{kind.inspect}"
      missing = spec[:required] - condition.keys
      raise ArgumentError, "#{label}: #{kind} needs #{missing.join(', ')}" if missing.any?
      unknown = condition.keys - [ "kind" ] - spec[:required] - spec[:optional]
      raise ArgumentError, "#{label}: #{kind} doesn't take #{unknown.join(', ')}" if unknown.any?

      TYPED.each do |param|
        raise ArgumentError, "#{label}: unknown type #{condition[param]}" if condition.key?(param) && !known.include?(condition[param])
      end
      if condition.key?("amount")
        most = kind == "drown" ? MAX_DROWN : 100
        raise ArgumentError, "#{label}: #{kind} amount is 1 to #{most}" unless condition["amount"].is_a?(Integer) && condition["amount"].between?(1, most)
      end
      condition.slice("kind", *spec[:required], *spec[:optional])
    end

    # The stage the field is at, or nil for a fight with no field.
    def current(state)
      field = state["field"] or return
      field["stages"][field["stage"]]
    end

    # The current stage's conditions of a kind.
    def of(state, kind)
      Array(current(state)&.dig("conditions")).select { |c| c["kind"] == kind }
    end

    # How much less a move of this type does on this field (a percent).
    def weakened(state, type)
      return 0 unless type

      of(state, "weaken").select { |c| c["type"] == type }.sum { |c| c["amount"] }.clamp(0, 100)
    end

    # The field's slowing, as buffs on top of a unit's own (Context#effective_stats).
    def buffs(state)
      of(state, "slow").map { |c| { "stat" => "agi", "amount" => -c["amount"], "turns" => 1 } }
    end

    def conducts?(state, type) = !type.nil? && of(state, "conduct").any? { |c| c["type"] == type }

    def dark(state) = of(state, "dark").sum { |c| c["amount"] }
  end
end
