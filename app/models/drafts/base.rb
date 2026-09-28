# frozen_string_literal: true

module Drafts
  # What every kind of Draft shares: the setting and the campaign, told to
  # the model in a few compact lines (a local model's context is small), and
  # the house voice.
  class Base
    # When a world hasn't said how it sounds.
    VOICE = "Small, pulp stories in a JRPG-flavoured world: a town burns, not the world; a gang, a debt, a haunted mill."
    RULES = "Be concrete, specific and playable at the table. Never name real people or real artists."

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
      { system: [ voice, instructions ].join(" "), user: [ context, ("The GM's idea: #{idea}" unless idea.empty?) ].compact.join("\n\n") }
    end

    # The world's own voice and limits (World#voice, #avoid, #lines, #veils).
    def voice
      [ "The setting's voice: #{world.voice.presence&.squish || VOICE}", RULES,
        ("Avoid: #{world.avoid.squish}." if world.avoid.present?),
        ("Never include, in any form: #{world.lines.squish}." if world.lines.present?),
        ("Keep these off-screen, never described: #{world.veils.squish}." if world.veils.present?) ].compact.join(" ")
    end

    private

    def routes = Rails.application.routes.url_helpers

    def clip(text, length = 160)
      text.to_s.squish.truncate(length)
    end

    # The world as the model sees it: its pitch, its lore (the GM's notes
    # too: this is for the GM), and the names in its atlas and cast.
    def setting
      codex = world.codex_entries.in_order.limit(12).map do |entry|
        "- #{entry.title}#{" (#{entry.category})" if entry.category}: #{clip([ entry.body, entry.gm_notes ].compact_blank.join(' '), 220)}"
      end
      [ "Setting: #{world.name}. #{clip(world.description, 400)}".strip,
        ("Lore:\n#{codex.join("\n")}" if codex.any?),
        ("Places in the setting: #{world.world_places.in_order.limit(20).map(&:name).join(', ')}." if world.world_places.exists?),
        ("People in the setting: #{world.world_figures.in_order.limit(20).map { |f| [ f.name, f.title ].compact_blank.join(', ') }.join('; ')}." if world.world_figures.exists?) ].compact.join("\n\n")
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
        seen = node.location&.town? && node.location.reputation.nonzero? ? "; sees the party as #{node.location.standing.downcase}" : ""
        "- #{node.name} (#{node.kind})#{"; can become: #{modes.join(', ')}" if modes.any?}#{seen}"
      end
    end

    def already
      [ *campaign.secrets.order(:id).limit(15).map { |s| "- secret: #{clip(s.body)}" },
        *campaign.clocks.order(:id).limit(10).map { |c| "- clock: #{c.name}" },
        *campaign.flags.order(:key).limit(15).map { |f| "- flag: #{f.key} = #{clip(f.value, 60)}" } ]
    end

    def deeds
      campaign.deeds.in_order.last(10).map { |d| "- day #{d.day}: #{clip(d.body)}" }
    end

    # The party, as people: job, origin, home and ties.
    def party
      campaign.characters.includes(:job, :home_node).order(:created_at).limit(8).map do |c|
        ties = c.tie_lines.map { |npc, text| [ npc&.name, text ].compact.join(": ") }
        "- #{c.name}, #{c.job.name}#{", #{c.origin_entry['name']}" if c.origin_entry}#{", home in #{c.home_node.name}" if c.home_node}" \
          "#{"; ties: #{ties.join('; ')}" if ties.any?}#{"; \"#{c.motive}\"" if c.motive.present?}"
      end
    end

    def campaign_context
      [ setting, "Campaign: #{campaign.name}.",
        "Party:\n#{party.join("\n").presence || '(no one yet)'}",
        "Cast:\n#{cast.join("\n").presence || '(none yet)'}",
        "Places:\n#{places.join("\n").presence || '(none yet)'}",
        "Already prepared:\n#{already.join("\n").presence || '(nothing yet)'}",
        ("What the party has done:\n#{deeds.join("\n")}" if deeds.any?) ].compact.join("\n\n")
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
