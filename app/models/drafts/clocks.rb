# frozen_string_literal: true

module Drafts
  # Clocks for prep (Clock): what happens if the party doesn't stop it.
  class Clocks < Base
    def instructions
      "You write clocks for the GM's prep: things that will happen if the party doesn't stop them, filling in steps. " \
        'Reply with JSON: {"clocks": [{"name": "what happens, a short sentence", "segments": 4 to 8, ' \
        '"ticks_on": ["rest", "travel", "failed_check"] (any of these, or none), ' \
        '"when_full": "the line the table hears when it happens", "public": true if the players can see it coming}]}, with 3 clocks.'
    end

    def context = campaign_context

    def items(json)
      rows(json, "clocks").filter_map do |row|
        name = clip(row["name"], 120)
        next if name.empty?

        { "name" => name, "segments" => (row["segments"].to_i.nonzero? || 6).clamp(2, 12),
          "triggers" => Array(row["ticks_on"]).map(&:to_s) & Clock::TRIGGERS.keys,
          "full_line" => clip(row["when_full"], 300).presence, "public" => row["public"] == true }.compact
      end.first(6)
    end

    def keep!(item)
      campaign.clocks.create!(name: item["name"], segments: item["segments"], triggers: item["triggers"],
                              full_line: item["full_line"], public: item["public"])
      { notice: "Clock “#{item['name']}” set." }
    end
  end
end
