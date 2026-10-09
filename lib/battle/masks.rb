# frozen_string_literal: true

module Battle
  # Masks (Oda's rare treasure): whoever puts one on transforms for a few
  # of their turns. Their stats rise (Stats::STATUS_MODIFIERS "masked"),
  # their Attack strikes with the mask's type, the mask's own moves join
  # their menu, and the board shows the mask's face. When it wears off they
  # are spent for a while; knocked out, it just comes off.
  #
  # A battle carries the masks its moves can put on (State.build masks:),
  # as plain data:
  #   { "storm_mask" => { "name" => "Storm Mask", "type" => "electric", "duration" => 3,
  #                       "abilities" => ["raijin"], "image" => {...} } }
  # A coward can't put one on (the mask won't have them).
  module Masks
    DEFAULT_DURATION = 3
    MAX_DURATION = 5
    # Turns a wearer is spent for once a mask wears off.
    SPENT_TURNS = 2
    # A masked blow against a giant (the giant trait).
    GIANT_POWER = 200

    module_function

    def validate!(masks, library, known)
      masks.each do |id, mask|
        raise ArgumentError, "mask #{id} is not a hash" unless mask.is_a?(Hash)

        mask["id"] = id
        mask["name"] ||= id.to_s.tr("_", " ").capitalize
        raise ArgumentError, "mask #{id}: unknown type #{mask['type']}" if mask["type"] && !known.include?(mask["type"])

        duration = mask.fetch("duration", DEFAULT_DURATION)
        raise ArgumentError, "mask #{id}: lasts 1 to #{MAX_DURATION} turns" unless duration.is_a?(Integer) && duration.between?(1, MAX_DURATION)

        missing = Array(mask["abilities"]) - library.keys
        raise ArgumentError, "mask #{id} grants unknown abilities: #{missing.join(', ')}" if missing.any?
      end
      masks
    end

    # transform(mask): the actor puts the mask on.
    def put_on(ctx, actor, effect)
      mask = ctx.state.fetch("masks", {})[effect["mask"]]
      return ctx.emit(:miss, actor: actor["id"], target: actor["id"], reason: "no_mask") unless mask
      return ctx.emit(:miss, actor: actor["id"], target: actor["id"], reason: "coward", mask: mask["id"]) if actor["coward"]
      if ctx.status?(actor, "masked") || ctx.status?(actor, "spent")
        return ctx.emit(:miss, actor: actor["id"], target: actor["id"], reason: "masked", mask: mask["id"])
      end

      granted = Array(mask["abilities"]) - actor["abilities"]
      actor["abilities"] += granted
      turns = mask.fetch("duration", DEFAULT_DURATION)
      actor["statuses"] << { "kind" => "masked", "turns" => turns, "mask" => mask["id"], "granted" => granted }
                           .merge(mask["type"] ? { "type" => mask["type"] } : {})
      ctx.emit(:transformed, actor: actor["id"], mask: mask["id"], name: mask["name"], image: mask["image"], turns: turns,
                             abilities: granted)
    end

    # The mask comes off (worn off, taken, or its wearer down): its moves go
    # with it. Worn off, the wearer is spent.
    def take_off(ctx, unit, status, spent:)
      unit["abilities"] -= Array(status["granted"])
      ctx.emit(:unmasked, unit: unit["id"], mask: status["mask"])
      ctx.add_status(unit, "spent", SPENT_TURNS) if spent && ctx.alive?(unit)
    end

    # The type a masked wearer's Attack strikes with.
    def type(unit)
      unit["statuses"].find { |s| s["kind"] == "masked" }&.dig("type")
    end
  end
end
