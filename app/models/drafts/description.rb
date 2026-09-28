# frozen_string_literal: true

module Drafts
  # A book entry's description, in the voice of the rest of its book. Only
  # words: its numbers stay the author's.
  class Description < Base
    def instructions
      "You write the description for one entry in a game's rulebook, in the same voice as the others in its book: " \
        "one or two short sentences, vivid and plain, saying what it is and what it does in play. " \
        'Reply with JSON: {"descriptions": ["...", "...", "..."]}, with 3 different takes.'
    end

    def context
      book = target.class
      others = book.where(world: world).where.not(id: target.id).where.not(description: [ nil, "" ]).order("RANDOM()").limit(4)
      [ setting,
        "The entry: #{target.name}, a #{book.model_name.human.downcase}. #{facts.join(' ')}".strip,
        ("Its description now: #{clip(target.description, 300)}" if target.description.present?),
        ("Others in the same book:\n#{others.map { |e| "- #{e.name}: #{clip(e.description, 200)}" }.join("\n")}" if others.any?) ].compact.join("\n\n")
    end

    def items(json)
      Array(json["descriptions"]).map { |text| clip(text, 500) }.reject(&:empty?).uniq.first(5).map { |text| { "text" => text } }
    end

    def keep!(item)
      target.update!(description: item["text"])
      { notice: "#{target.name} has a new description." }
    end

    private

    # What the model needs to know about it, in a few words.
    def facts
      case target
      when Monster then [ "Level #{target.level}.", ("Type: #{world.type_chart.name(target.base_type)}." if world.type_chart.matter?) ]
      when Ability then [ "A #{target.kind} that aims at #{target.target.to_s.humanize.downcase}.",
                          "Effects: #{Array(target.effects).map { |e| e.slice('primitive', 'type', 'kind').values.join(' ') }.join('; ')}." ]
      when Item then [ "A #{target.category}, #{target.price} #{world.word('currency')}." ]
      when Job then [ ("Type: #{world.type_chart.name(target.base_type)}." if world.type_chart.matter?) ]
      else []
      end.compact
    end
  end
end
