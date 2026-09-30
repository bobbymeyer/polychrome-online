# frozen_string_literal: true

module Drafts
  # Modes for a place on the map (MapNode#add_mode!): the city burns, the mine floods.
  class Mode < Base
    def instructions
      "You write modes for one place: another state it can be in for a while, set off at the table " \
        "(the town burns, the mine floods, the festival starts). The rest of the world stays as it is. " \
        'Reply with JSON: {"modes": [{"name": "one or two words", "line": "what the table hears when it starts", ' \
        '"description": "what players read about the place meanwhile", "closed": [services shut meanwhile, from the list], ' \
        "\"music\": one of #{Campaign::MUSIC_CHOICES.join(', ')} or null, " \
        '"art": "a few words for how its picture changes"}]}, with 3 modes.'
    end

    def context
      view = target.location&.view || { "description" => target.description }
      services = self.services
      [ campaign_context,
        "The place: #{target.name}, a #{target.kind}#{" (#{clip(view['description'], 200)})" if view['description'].present?}.",
        "Its services: #{services.join(', ').presence || 'none'}.",
        ("It can already become: #{target.modes.map { |m| m['name'] }.join(', ')}." if target.modes.any?) ].compact.join("\n\n")
    end

    def items(json)
      rows(json, "modes").filter_map do |row|
        name = clip(row["name"], 40)
        next if name.empty?

        { "name" => name, "line" => clip(row["line"], 300).presence, "description" => clip(row["description"], 300).presence,
          "closed" => Array(row["closed"]).map(&:to_s) & services,
          "music" => (row["music"].to_s if Campaign::MUSIC_CHOICES.include?(row["music"].to_s)),
          "art" => clip(row["art"], 200).presence }.compact
      end.first(5)
    end

    # What a mode can shut there: a town's services.
    def services = target.location&.town? ? target.location.view.fetch("services", []).map { |s| s["kind"] }.uniq : []

    def keep!(item)
      target.add_mode!(item.except("kept"))
      { notice: "#{item['name']} is ready to set off." }
    end
  end
end
