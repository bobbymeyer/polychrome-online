# frozen_string_literal: true

module Drafts
  # Secrets for prep (Secret): true things the party could find out, tying
  # together the cast and places already in the campaign.
  class Secrets < Base
    def instructions
      "You write secrets for the GM's prep: facts that are true in this campaign but the players don't know yet, " \
        "which they could find out more than one way. Tie them to the cast and places already there where you can. " \
        'Reply with JSON: {"secrets": [{"text": "one sentence", "place": "a place from the list, or null", ' \
        '"person": "someone from the cast, or null"}]}, with 6 secrets. Don\'t repeat what\'s already prepared.'
    end

    def context = campaign_context

    def items(json)
      rows(json, "secrets").filter_map do |row|
        text = clip(row["text"], 500)
        next if text.empty?

        { "text" => text, "place" => location_named(row["place"])&.name, "person" => npc_named(row["person"])&.name }.compact
      end.first(10)
    end

    def keep!(item)
      campaign.secrets.create!(body: item["text"], location: location_named(item["place"]), npc: npc_named(item["person"]))
      { notice: "Secret kept." }
    end
  end
end
