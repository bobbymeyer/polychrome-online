# frozen_string_literal: true

# A line at the table (docs/HANDOFF.md §4, §7).
#
# Speakers are characters (players), NPCs (the GM possessing them) or
# nobody (the GM narrating). How a line is shown settles §9.5: GM and NPC
# lines go through the dialogue box one at a time, player lines go straight
# into the side log, and whispers only ever go to the log.
#
# Whispers are scoped broadcasts: a whisper is streamed only to the GM and
# to the one character involved, never to the whole table.
class Message < ApplicationRecord
  KINDS = %w[say system].freeze
  SCOPES = %w[table whisper].freeze
  SPEAKER_TYPES = %w[Character Npc].freeze

  belongs_to :campaign
  belongs_to :speaker, polymorphic: true, optional: true
  belongs_to :recipient, class_name: "Character", optional: true
  belongs_to :battle, class_name: "BattleRecord", optional: true

  normalizes :body, with: ->(body) { body.to_s.strip }
  normalizes :expression, with: ->(expression) { expression.presence }

  validates :body, presence: true, length: { maximum: 2000 }
  validates :kind, inclusion: { in: KINDS }
  validates :scope, inclusion: { in: SCOPES }
  validates :speaker_type, inclusion: { in: SPEAKER_TYPES }, allow_nil: true
  validates :expression, inclusion: { in: Portrait::EXPRESSIONS }, allow_nil: true
  validate :everyone_is_at_this_table
  validate :whispers_have_two_ends

  scope :chronological, -> { order(:created_at, :id) }

  after_create_commit :broadcast

  def whisper?
    scope == "whisper"
  end

  def system?
    kind == "system"
  end

  def from_gm?
    !speaker.is_a?(Character)
  end

  # GM and NPC lines at the table play through the dialogue box.
  def dialogue?
    !whisper? && !system? && from_gm?
  end

  # The character on the other end of a whisper.
  def whisper_character
    speaker.is_a?(Character) ? speaker : recipient
  end

  def speaker_name
    speaker&.name || "Narrator"
  end

  # seat: "gm", a Character, or nil for someone just watching.
  def visible_to?(seat)
    return true unless whisper?
    return true if seat == "gm"

    seat.is_a?(Character) && seat == whisper_character
  end

  # Every stream this message goes to.
  def streams
    whisper? ? [ [ campaign, :gm ], [ whisper_character, :whispers ] ] : [ [ campaign, :table ] ]
  end

  # Messages a seat may see, oldest first.
  def self.visible_to(campaign, seat)
    lines = campaign.messages.includes(:speaker, :recipient, :battle)
    lines = if seat == "gm" then lines
    elsif seat.is_a?(Character)
      lines.where(scope: "table")
           .or(lines.where(scope: "whisper", speaker_type: "Character", speaker_id: seat.id))
           .or(lines.where(scope: "whisper", recipient_id: seat.id))
    else lines.where(scope: "table")
    end
    lines.chronological
  end

  private

  def broadcast
    streams.each do |stream|
      broadcast_append_to(*stream, target: "chat_log", partial: "messages/message", locals: { message: self, live: true })
    end
  end

  def everyone_is_at_this_table
    errors.add(:speaker, "isn't in this campaign") if speaker && speaker.campaign_id != campaign_id
    errors.add(:recipient, "isn't in this campaign") if recipient && recipient.campaign_id != campaign_id
    errors.add(:battle, "isn't in this campaign") if battle && battle.campaign_id != campaign_id
  end

  # A player whispers to the GM; the GM (as narrator or an NPC) whispers to
  # a player.
  def whispers_have_two_ends
    if whisper?
      if speaker.is_a?(Character)
        errors.add(:recipient, "must be empty: players whisper to the GM") if recipient
      elsif recipient.nil?
        errors.add(:recipient, "is needed for a GM whisper")
      end
    elsif recipient
      errors.add(:recipient, "is only for whispers")
    end
  end
end
