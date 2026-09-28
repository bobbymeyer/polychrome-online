# frozen_string_literal: true

module Drafts
  # What every kind of Draft shares: the setting and the campaign, told to
  # the model in a few compact lines (a local model's context is small), and
  # the house voice.
  class Base
    VOICE = "The GM tells small, pulp stories in a JRPG-flavoured world: a town burns, not the world; a gang, a debt, " \
            "a haunted mill. Be concrete, specific and playable at the table. Never name real people or real artists."

    attr_reader :draft

    def initialize(draft)
      @draft = draft
    end

    def owner = draft.owner
    def request = draft.request
    def idea = request["idea"].to_s.strip
    def world = owner.is_a?(World) ? owner : owner.world
    def campaign = (owner if owner.is_a?(Campaign))
    def target = draft.target_record

    # { system:, user: } for Llm::Client#json.
    def messages
      { system: "#{VOICE} #{instructions}", user: [ context, ("The GM's idea: #{idea}" unless idea.empty?) ].compact.join("\n\n") }
    end

    private

    def routes = Rails.application.routes.url_helpers

    def clip(text, length = 160)
      text.to_s.squish.truncate(length)
    end

    def setting
      "Setting: #{world.name}. #{clip(world.description, 400)}".strip
    end

    # --- the campaign as the model sees it --------------------------------

    def cast
      campaign.npcs.order(:name).limit(20).map do |npc|
        "- #{npc.name}#{", #{npc.title}" if npc.title.present?}#{": #{clip(npc.description)}" if npc.description.present?}"
      end
    end

    def places
      campaign.map_nodes.includes(:location).order(:name).limit(20).map do |node|
        modes = node.location&.modes.to_a.map { |m| m["name"] }
        "- #{node.name} (#{node.kind})#{"; can become: #{modes.join(', ')}" if modes.any?}"
      end
    end

    def already
      [ *campaign.secrets.order(:id).limit(15).map { |s| "- secret: #{clip(s.body)}" },
        *campaign.clocks.order(:id).limit(10).map { |c| "- clock: #{c.name}" },
        *campaign.flags.order(:key).limit(15).map { |f| "- flag: #{f.key} = #{clip(f.value, 60)}" } ]
    end

    def campaign_context
      [ setting, "Campaign: #{campaign.name}.",
        "Cast:\n#{cast.join("\n").presence || '(none yet)'}",
        "Places:\n#{places.join("\n").presence || '(none yet)'}",
        "Already prepared:\n#{already.join("\n").presence || '(nothing yet)'}" ].join("\n\n")
    end

    # A place or person the model named, found in the campaign by name.
    def location_named(name)
      name = name.to_s.strip
      return nil if name.empty?

      node = campaign.map_nodes.includes(:location).find { |n| n.name.casecmp?(name) || n.location&.name.to_s.casecmp?(name) }
      node&.location
    end

    def npc_named(name)
      name = name.to_s.strip
      campaign.npcs.find { |n| n.name.casecmp?(name) } unless name.empty?
    end

    def rows(json, key)
      Array(json.is_a?(Hash) ? json[key] : json).select { |row| row.is_a?(Hash) }
    end
  end
end
