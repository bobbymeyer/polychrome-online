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
  KINDS = %w[say system choice].freeze
  # "? Trust Cid | Refuse -> trusted_cid": a choice for the table, with the
  # flag its outcome sets (scenes and the GM's composer both take it).
  CHOICE = /\A\?\s*(?<options>[^>]+?)(?:\s*->\s*(?<flag>[\w ]+))?\s*\z/
  MAX_OPTIONS = 6
  # The jingle a line plays as it arrives (sound.js).
  CUES = %w[key door treasure check jobs].freeze
  # table: everyone; whisper: a player and the GM; gm: a note for the GM alone.
  SCOPES = %w[table whisper gm].freeze
  SPEAKER_TYPES = %w[Character Npc].freeze

  belongs_to :campaign
  belongs_to :speaker, polymorphic: true, optional: true
  belongs_to :recipient, class_name: "Character", optional: true
  belongs_to :battle, class_name: "BattleRecord", optional: true
  has_many :picks, class_name: "ChoicePick", dependent: :delete_all

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
  validate :choices_have_options

  scope :chronological, -> { order(:created_at, :id) }

  after_create_commit :broadcast
  after_create_commit :broadcast_choice, if: :choice?
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

  # GM and NPC lines at the table play through the dialogue box.
  def dialogue?
    kind == "say" && !whisper? && from_gm?
  end

  def choice?
    kind == "choice"
  end

  # { options:, flag: } from "? A | B -> flag", or nil if it isn't a choice.
  def self.parse_choice(text)
    match = CHOICE.match(text.to_s.strip) or return
    options = match[:options].split("|").map(&:strip).reject(&:empty?)
    return if options.size < 2

    { options: options, flag: match[:flag]&.strip.presence }
  end

  # A choice for the table, from "? A | B -> flag".
  def self.choice(campaign, options:, flag: nil)
    campaign.messages.new(kind: "choice", options: options, flag_key: flag,
                          body: "The party decides: #{options.to_sentence(two_words_connector: ' or ', last_word_connector: ', or ')}.")
  end

  def open_choice?
    choice? && settled.nil?
  end

  # { option => [character names] }, in the options' order.
  def tally
    names = picks.includes(:character).group_by(&:option).transform_values { |ps| ps.map { |p| p.character.name } }
    options.index_with { |option| names.fetch(option, []) }
  end

  # The GM settles it: the outcome is said, and set as a flag the party
  # knows, for the GM's next scene to follow.
  def settle!(option)
    raise Refusal, "That isn't one of the options" unless options.include?(option)
    raise Refusal, "This was settled already" unless open_choice?

    transaction do
      update!(settled: option)
      if flag_key
        flag = campaign.flags.find_or_initialize_by(key: Flag.new(key: flag_key).key)
        flag.update!(value: option, public: true)
      end
      campaign.narrate("The party chose: #{option}.")
    end
    broadcast_choice
    streams.each { |stream| broadcast_replace_to(*stream, target: self, partial: "messages/message", locals: { message: self }) }
  end

  # The table's choice panel shows the open choice, if there is one.
  def broadcast_choice
    broadcast_replace_to(campaign, :table, target: "table_choice", partial: "choices/panel", locals: { choice: campaign.open_choice })
  end

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
  def choices_have_options
    return unless choice?

    errors.add(:options, "need at least two") if options.size < 2
    errors.add(:options, "can be at most #{MAX_OPTIONS}") if options.size > MAX_OPTIONS
    errors.add(:options, "must be different") if options.uniq.size != options.size
    errors.add(:scope, "must be the whole table") if whisper?
  end

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
