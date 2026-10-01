# frozen_string_literal: true

# What a camp or road event offers the table (docs/STORY.md, item 10),
# written on its row: options with "|" between them, each with what it
# does after a colon (Outcome::ON_A_CHOICE), and the flag the table's
# answer sets after "->", as a choice the GM puts is written:
#
#   Share the fire: give potion, rumour | Send her off: tick -> helped_stranger
#
# Two things the table values against each other, each with its price.
# Put to the table as a choice (Message::Choice), the option the GM
# settles on does what it says, and the flag remembers which it was.
EventChoices = Data.define(:options, :flag)

class EventChoices
  # [choices, problems]; choices is nil for a row that offers none.
  def self.parse(text)
    text = text.to_s.strip
    return [ nil, [] ] if text.empty?

    body, flag = text.split("->", 2).map(&:strip)
    problems = []
    options = body.split("|").map(&:strip).reject(&:empty?).map do |part|
      label, does = part.split(":", 2).map(&:strip)
      outcomes = does.to_s.split(",").map(&:strip).reject(&:empty?)
      outcomes.each do |word|
        outcome = Outcome.parse(word)
        problems << "“#{label}”: #{word} isn't something a choice can do (#{Outcome::ON_A_CHOICE.first(6).join(', ')}, give potion…)" unless outcome && Outcome::ON_A_CHOICE.include?(outcome.kind)
      end
      { "label" => label, "does" => outcomes }
    end
    problems << "A choice needs two options or more, with | between them" if options.size < 2
    problems << "Each option needs its own words" if options.map { |o| o["label"] }.uniq.size != options.size || options.any? { |o| o["label"].blank? }
    problems << "At most #{Message::Choice::MAX_OPTIONS} options" if options.size > Message::Choice::MAX_OPTIONS
    problems << "“#{flag}” can't be a flag: letters, digits and underscores" if flag && !flag.match?(/\A[a-z][a-z0-9_]*\z/i)
    [ new(options: options, flag: flag.presence&.downcase), problems ]
  end

  # The options whose every outcome could happen now and would do
  # something (Outcome#bites?, #can_happen!).
  def possible(campaign)
    options.select do |option|
      option["does"].all? do |word|
        outcome = Outcome.parse(word)
        outcome.can_happen!(campaign)
        outcome.bites?(campaign)
      rescue Refusal
        false
      end
    end
  end
end
