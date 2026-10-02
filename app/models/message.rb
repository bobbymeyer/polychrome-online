# frozen_string_literal: true

# A line at the table (docs/HANDOFF.md §4, §7).
#
# Speakers are characters (players), NPCs (the GM possessing them) or
# nobody (the GM narrating). How a line is shown settles §9.5: GM and NPC
# lines go through the dialogue box one at a time, player lines go straight
# into the side log, and whispers only ever go to the log.
#
# Whispers are scoped broadcasts: a whisper is streamed only to the GM and
# to the one character involved, never to the whole table. A choice for
# the table is a line too (Message::Choice).
class Message < ApplicationRecord
  KINDS = %w[say system choice].freeze
  # The jingle a line plays as it arrives (sound.js).
  CUES = %w[key door treasure check jobs cleared deadline awakening arrival].freeze
  # table: everyone; whisper: a player and the GM; gm: a note for the GM alone.
  SCOPES = %w[table whisper gm].freeze
  SPEAKER_TYPES = %w[Character Npc].freeze

  belongs_to :campaign
  belongs_to :speaker, polymorphic: true, optional: true
  belongs_to :recipient, class_name: "Character", optional: true
  belongs_to :battle, class_name: "BattleRecord", optional: true

  normalizes :body, with: ->(body) { body.to_s.strip }
  normalizes :expression, with: ->(expression) { expression.presence }

  validates :body, presence: true, length: { maximum: 2000 }
  validates :kind, inclusion: { in: KINDS }
  validates :cue, inclusion: { in: CUES }, allow_nil: true
  validates :scope, inclusion: { in: SCOPES }
  validates :speaker_type, inclusion: { in: SPEAKER_TYPES }, allow_nil: true
  validates :expression, inclusion: { in: Portrait::EXPRESSIONS }, allow_nil: true
  validate :everyone_is_at_this_table
  validate :whispers_have_two_ends

  scope :chronological, -> { order(:created_at, :id) }

  before_create :mark_story_time
  after_create_commit :broadcast
  include Choice # after the line itself goes out, the choice panel
  # An NPC speaking at the table reminds whoever is tied to them (Campaign::Belonging).
  after_create_commit -> { campaign.remind_ties!(speaker) }, if: -> { speaker.is_a?(Npc) && scope == "table" && kind == "say" }
  # And, if they're behind a secret, its next clue is offered to the GM (Campaign::Remarks).
  after_create_commit -> { campaign.offer_clue_from!(speaker) }, if: -> { speaker.is_a?(Npc) && scope == "table" && kind == "say" }
  after_destroy_commit { streams.each { |stream| broadcast_remove_to(*stream) } }

  def whisper?
    scope == "whisper"
  end

  def gm_only?
    scope == "gm"
  end

  def system?
    kind == "system"
  end

  def from_gm?
    !speaker.is_a?(Character)
  end

  # GM and NPC lines at the table play through the dialogue box; so does
  # every line of a scene, a character's included (the GM wrote it for them).
  def dialogue?
    kind == "say" && !whisper? && (from_gm? || scene?)
  end

  # Said by a scene's beat (Scene#show!).
  def scene? = data.to_h["scene"].present?

  # The character on the other end of a whisper.
  def whisper_character
    speaker.is_a?(Character) ? speaker : recipient
  end

  def speaker_name
    speaker&.name || "Narrator"
  end

  # Every stream this message goes to.
  def streams
    return [ [ campaign, :gm ] ] if gm_only?

    whisper? ? [ [ campaign, :gm ], [ whisper_character, :whispers ] ] : [ [ campaign, :table ] ]
  end

  # Messages a seat may see, oldest first (the query for Seat#sees?).
  def self.visible_to(campaign, seat)
    lines = campaign.messages.includes(:speaker, :recipient, :battle)
    lines = if seat.gm? then lines
    elsif seat.character?
      lines.where(scope: "table")
           .or(lines.where(scope: "whisper", speaker_type: "Character", speaker_id: seat.character.id))
           .or(lines.where(scope: "whisper", recipient_id: seat.character.id))
    else lines.where(scope: "table")
    end
    lines.chronological
  end

  # "Dusk", or, for a line said before the story kept time, nothing.
  def story_time
    time_of_day&.upcase_first
  end

  private

  # When in the story it was said, from the campaign's clock.
  def mark_story_time
    self.day ||= campaign&.day
    self.time_of_day ||= campaign&.time_of_day
  end

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
