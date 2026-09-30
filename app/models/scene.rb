# frozen_string_literal: true

# A scene the GM prepares before the session and plays at the table with one
# press: its lines go out one after another through the dialogue box, then
# it ends, in a battle, with a place revealed on the map, or with a place
# changed (its ending is an Outcome, as a full clock's is).
#
# The script reads like a play, one line each:
#
#   Cid (worried): The airship won't hold.
#   The wind picks up.
#   Narrator: A shadow crosses the moon.
#
# A line starting with an NPC's name and a colon is theirs, with an optional
# expression in brackets. Anything else is the narrator's. The last line can
# put a choice to the table: "? Trust Cid | Refuse -> trusted_cid".
class Scene < ApplicationRecord
  ENDINGS = %w[none battle reveal mode].freeze
  LINE = /\A(?<name>[^:()]+?)\s*(?:\((?<expression>[^)]*)\))?\s*:\s*(?<text>.+)\z/
  # Longer than this before the colon, it's narration that has a colon in it.
  NAME_WORDS = 3

  include CampaignPages

  belongs_to :campaign
  belongs_to :map_node, optional: true
  # A "mode" ending sets this mode off; without one, the place goes back
  # to how it was.
  belongs_to :location_mode, optional: true

  normalizes :name, with: ->(name) { name.to_s.strip }

  validates :name, presence: true
  validates :ending, inclusion: { in: ENDINGS }
  validate :script_reads
  validate :ending_is_complete

  scope :in_order, -> { order(Arel.sql("played_at IS NOT NULL"), :created_at, :id) }

  def played?
    played_at.present?
  end

  # [{ "speaker" => Npc or nil, "expression", "text", "problem" }]
  def lines
    npcs = campaign.npcs.to_a
    script.to_s.lines.map(&:strip).reject(&:empty?).map { |raw| read(raw, npcs) }
  end

  # One line of a script, read as a scene reads it: an NPC's (with an
  # expression), the narrator's, or narration with a colon in it ("Tsukiura
  # Station, 0:09."). A boss's entrance is read the same way.
  #   { "speaker" => Npc or nil, "expression", "text", "problem" }
  def self.read_line(raw, npcs)
    match = LINE.match(raw)
    return { "speaker" => nil, "expression" => nil, "text" => raw } unless match

    name = match[:name].strip
    expression = match[:expression].to_s.strip.downcase.presence
    line = { "speaker" => nil, "expression" => expression, "text" => match[:text].strip }
    return line if name.casecmp?("narrator")

    npc = npcs.find { |n| n.name.casecmp?(name) }
    return line.merge("speaker" => npc) if npc
    # Not a name: too long, or a time or a place and a time ("Tsukiura Station, 0:09.").
    return { "speaker" => nil, "expression" => nil, "text" => raw } if name.split.size > NAME_WORDS || name.match?(/[\d,]/) || line["text"].match?(/\A\d/)

    line.merge("problem" => "#{name} isn't in the cast. Add them as an NPC, or start the line with “Narrator:”.")
  end

  # The lines go to the table in order, then the ending plays. A battle
  # starts last, so everyone reads the scene before the stage takes them
  # there (stage.js waits for the dialogue box).
  def play!
    outcome&.can_happen!(campaign)

    transaction do
      lines.each do |line|
        next Message.choice(campaign, **line["choice"]).save! if line["choice"]

        campaign.messages.create!(speaker: line["speaker"], expression: line["expression"], body: line["text"])
      end
      unless ending == "battle"
        said = outcome&.apply!(campaign, by: name)
        campaign.narrate(said) if said
      end
      update!(played_at: Time.current)
    end
    return unless ending == "battle"

    outcome.apply!(campaign, by: name)
    campaign.battles.order(:id).last # the fight it started
  end

  # How it ends, as the game's outcomes (Outcome): a fight, a place
  # revealed, a place set in a mode or back to how it was. Nil for none.
  def outcome
    case ending
    when "battle" then Outcome.of("battle", target: { "name" => name, "monsters" => encounter })
    when "reveal" then map_node && Outcome.of("reveal", target: { "node" => map_node.id })
    when "mode" then map_node && Outcome.of("mode", target: { "node" => map_node.id, "mode" => location_mode&.key })
    end
  end

  def summary
    said = lines.reject { |l| l["choice"] }
    parts = [ ActionController::Base.helpers.pluralize(said.size, "line") ]
    parts << "then a choice: #{lines.last['choice'][:options].join(' / ')}" if lines.last&.dig("choice")
    parts << "then a battle: #{campaign.describe_encounter(encounter)}" if ending == "battle"
    parts << "then #{map_node&.name || 'a place'} appears on the map" if ending == "reveal"
    if ending == "mode"
      parts << (location_mode ? "then #{map_node&.name}: #{location_mode.name}" : "then #{map_node&.name} goes back to how it was")
    end
    parts.join(", ")
  end

  private

  def read(raw, npcs)
    if raw.start_with?("?")
      choice = Message.parse_choice(raw)
      return { "choice" => choice } if choice

      return { "text" => raw, "problem" => "A choice needs two options or more: “? Trust Cid | Refuse -> trusted_cid”." }
    end

    self.class.read_line(raw, npcs)
  end

  def script_reads
    lines.each do |line|
      errors.add(:script, line["problem"]) if line["problem"]
      if line["choice"] && line != lines.last
        errors.add(:script, "can only end on a choice, with nothing after it: the next scene can follow what the party chose")
      elsif line["choice"] && ending != "none"
        errors.add(:ending, "can't follow a choice: a scene that ends on a choice leaves what happens next to the party. " \
                            "Set “When the last line is said” to Nothing, or make the fight a scene of its own")
      end
      if line["expression"] && !Portrait::EXPRESSIONS.include?(line["expression"])
        errors.add(:script, "“#{line['expression']}” isn't an expression. Use one of #{Portrait::EXPRESSIONS.to_sentence(last_word_connector: ' or ')}.")
      end
    end
    errors.add(:script, "is empty, and the scene has no ending") if lines.empty? && ending == "none"
  end

  def ending_is_complete
    case ending
    when "battle"
      known = campaign.world.monsters.where(slug: encounter.keys).pluck(:slug)
      errors.add(:encounter, "needs a monster from the Bestiary") if encounter.empty? || (encounter.keys - known).any?
    when "reveal"
      errors.add(:map_node, "must be a place on this campaign's map") unless map_node && map_node.campaign_id == campaign_id
    when "mode"
      if map_node&.campaign_id != campaign_id
        errors.add(:map_node, "must be a place on this campaign's map")
      elsif location_mode && location_mode.map_node_id != map_node.id
        errors.add(:location_mode, "isn't one of #{map_node.name}'s modes")
      end
    end
  end
end
