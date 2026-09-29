# frozen_string_literal: true

module Battle
  # Using an item outside battle, from the party's menu. Pure: the same
  # Effects formulas as in battle, so a Potion heals the same either way;
  # randomness comes from the RNG state passed in, and the new state comes
  # back out.
  #
  # Only healing and revival mean anything outside battle: statuses and buffs
  # live only as long as a battle does.
  module Field
    PRIMITIVES = %w[heal revive].freeze

    module_function

    def usable?(item)
      effects = item.fetch("effects", [])
      effects.any? && effects.all? { |e| PRIMITIVES.include?(e["primitive"]) } && %w[single_ally self].include?(item["target"])
    end

    # item: { "name", "target", "effects" }; user, target: party unit specs
    # (Character#battle_spec); types: the world's (Battle::Types). Returns
    # [target_hp, events, new_rng_state]. Raises InvalidAction when the item
    # would do nothing.
    def use_item(item, user:, target:, rng:, types: nil)
      raise InvalidAction, "#{item['name']} can only be used in battle" unless usable?(item)

      target = user if item["target"] == "self"
      revives = State.revives?(item)
      down = target.fetch("hp").zero?
      raise InvalidAction, "#{target['name']} is down: #{item['name']} won't help" if down && !revives
      raise InvalidAction, "#{target['name']} isn't down" if revives && !down
      raise InvalidAction, "#{target['name']} is already at full HP" if !revives && target["hp"] >= target["stats"]["max_hp"]

      units = [ user, target ].uniq { |u| u["id"] }.map { |u| u.merge("abilities" => []).except("desperation") }
      state = State.build(seed: 0, party: units, enemies: [], types: types)
      state["rng"] = rng
      ctx = Context.new(state)
      actor = ctx.unit(user["id"])
      receiver = ctx.unit(target["id"])
      item["effects"].each { |effect| Effects.apply(ctx, actor, receiver, effect.merge("item" => true)) }
      after, events = ctx.finish
      [ after["units"].find { |u| u["id"] == target["id"] }["hp"], events, after["rng"] ]
    end
  end
end
