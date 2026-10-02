# frozen_string_literal: true

# A line that asks the table to decide ("? Trust Cid | Refuse -> trusted_cid"):
# players pick (ChoicePick), the GM settles it, and the outcome is said, set
# as a flag, and, for a Where next? or a What now?, made as the party's move.
module Message::Choice
  extend ActiveSupport::Concern

  # "? Trust Cid | Refuse -> trusted_cid": a choice for the table, with the
  # flag its outcome sets (scenes and the GM's composer both take it).
  CHOICE = /\A\?\s*(?<options>[^>]+?)(?:\s*->\s*(?<flag>[\w ]+))?\s*\z/
  MAX_OPTIONS = 6

  included do
    has_many :picks, class_name: "ChoicePick", dependent: :delete_all

    validate :choices_have_options
    after_create_commit :broadcast_choice, if: :choice?
  end

  class_methods do
    # { options:, flag: } from "? A | B -> flag", or nil if it isn't a choice.
    def parse_choice(text)
      match = CHOICE.match(text.to_s.strip) or return
      options = match[:options].split("|").map(&:strip).reject(&:empty?)
      return if options.size < 2

      { options: options, flag: match[:flag]&.strip.presence }
    end

    # A choice for the table, from "? A | B -> flag".
    def choice(campaign, options:, flag: nil)
      campaign.messages.new(kind: "choice", options: options, flag_key: flag,
                            body: "The party decides: #{options.to_sentence(two_words_connector: ' or ', last_word_connector: ', or ')}.")
    end
  end

  def choice?
    kind == "choice"
  end

  def open_choice?
    choice? && settled.nil?
  end

  # A "Where next?" (Campaign::Ways): its options carry the party's moves.
  def where_next?
    choice? && data.key?("moves") && !data["recovery"]
  end

  # "Everyone is KO'd. What happens now?" (Campaign::Defeat#ask_what_now!).
  def what_now? = choice? && data["recovery"].present?

  # { option => [character names] }, in the options' order.
  def tally
    names = picks.includes(:character).group_by(&:option).transform_values { |ps| ps.map { |p| p.character.name } }
    options.index_with { |option| names.fetch(option, []) }
  end

  # The GM settles it: the outcome is said, and set as a flag, for the GM's
  # next scene to follow.
  def settle!(option)
    raise Refusal, "That isn't one of the options" unless options.include?(option)
    raise Refusal, "This was settled already" unless open_choice?
    raise Refusal, "Not while a battle is on: settle it once the battle is over" if campaign.battle_on?

    transaction do
      update!(settled: option)
      campaign.make_move!(data.dig("moves", option)) if data.dig("moves", option)
      if flag_key
        flag = campaign.flags.find_or_initialize_by(key: Flag.new(key: flag_key).key)
        flag.update!(value: option)
      end
      campaign.narrate("The party chose: #{option}.")
      do_what_it_says!(option)
    end
    broadcast_choice
    streams.each { |stream| broadcast_replace_to(*stream, target: self, partial: "messages/message", locals: { message: self }) }
  end

  # The table's choice panel shows the open choice, if there is one; the
  # ways on wait while the table decides something else.
  def broadcast_choice
    broadcast_replace_to(campaign, :table, target: "table_choice", partial: "choices/panel", locals: { choice: campaign.open_choice })
    campaign.table_changed
  end

  private

  # An event's option does what it says (Outcome), each in turn; what
  # can't happen any more (the potion was drunk meanwhile) is let go.
  def do_what_it_says!(option)
    Array(data.dig("outcomes", option)).each do |word|
      outcome = Outcome.parse(word) or next
      outcome.can_happen!(campaign)
      said = outcome.apply!(campaign, by: "The party")
      campaign.narrate(said) if said
    rescue Refusal
      next
    end
  end

  def choices_have_options
    return unless choice?

    errors.add(:options, "need at least two") if options.size < 2
    errors.add(:options, "can be at most #{MAX_OPTIONS}") if options.size > MAX_OPTIONS
    errors.add(:options, "must be different") if options.uniq.size != options.size
    errors.add(:scope, "must be the whole table") if whisper?
  end
end
