# frozen_string_literal: true

# A scene the GM prepares before the session and plays at the table with one
# press: its lines go out one after another through the dialogue box, then
# it ends, in a battle or with a place revealed on the map.
#
# The script reads like a play, one line each:
#
#   Cid (worried): The airship won't hold.
#   The wind picks up.
#   Narrator: A shadow crosses the moon.
#
# A line starting with an NPC's name and a colon is theirs, with an optional
# expression in brackets. Anything else is the narrator's.
class Scene < ApplicationRecord
  ENDINGS = %w[none battle reveal].freeze
  LINE = /\A(?<name>[^:()]+?)\s*(?:\((?<expression>[^)]*)\))?\s*:\s*(?<text>.+)\z/
  # Longer than this before the colon, it's narration that has a colon in it.
  NAME_WORDS = 3

  belongs_to :campaign
  belongs_to :map_node, optional: true

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

  # The lines go to the table in order, then the ending plays. A battle
  # starts last, so everyone reads the scene before the stage takes them
  # there (stage.js waits for the dialogue box).
  def play!
    raise ArgumentError, "Nobody is standing to fight" if ending == "battle" && campaign.characters.none?(&:conscious?)

    transaction do
      lines.each do |line|
        campaign.messages.create!(speaker: line["speaker"], expression: line["expression"], body: line["text"])
      end
      if ending == "reveal" && map_node && !map_node.visible?
        map_node.update!(visible: true)
        campaign.messages.create!(kind: "system", body: "#{map_node.name} appears on the map.")
      end
      update!(played_at: Time.current)
    end
    return unless ending == "battle"

    campaign.update!(pending_encounter: { "table" => name, "monsters" => encounter, "boss" => false })
    campaign.start_pending_encounter!
  end

  def summary
    parts = [ ActionController::Base.helpers.pluralize(lines.size, "line") ]
    parts << "then a battle: #{campaign.describe_encounter(encounter)}" if ending == "battle"
    parts << "then #{map_node&.name || 'a place'} appears on the map" if ending == "reveal"
    parts.join(", ")
  end

  private

  def read(raw, npcs)
    match = LINE.match(raw)
    return { "speaker" => nil, "expression" => nil, "text" => raw } unless match

    name = match[:name].strip
    expression = match[:expression].to_s.strip.downcase.presence
    line = { "speaker" => nil, "expression" => expression, "text" => match[:text].strip }
    return line if name.casecmp?("narrator")

    npc = npcs.find { |n| n.name.casecmp?(name) }
    return line.merge("speaker" => npc) if npc
    return { "speaker" => nil, "expression" => nil, "text" => raw } if name.split.size > NAME_WORDS

    line.merge("problem" => "#{name} isn't in the cast. Add them as an NPC, or start the line with “Narrator:”.")
  end

  def script_reads
    lines.each do |line|
      errors.add(:script, line["problem"]) if line["problem"]
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
    end
  end
end
