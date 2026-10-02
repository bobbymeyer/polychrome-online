# frozen_string_literal: true

# A step on the way to a secret (docs/STORY.md, item 11; ch. 14, 7, 8 of
# Procedural Storytelling in Game Design), from a question to the truth.
# Written one per line, vaguest first, the first a question; a clue
# someone tells, rather than one the party sees, says who after "|", so
# clues can disagree and the party knows whose word it is:
#
#   Why is the mayor's lamp lit at midnight?
#   Someone leaves the mayor's house before dawn, by the back gate.
#   The mayor's sick, and the lamp is for the doctor. | Mara Vell
#   Grave-coin in the mayor's strongbox.
#
# Each found gives the party the next one, wherever it was found (Secret
# #find_clue!); after the last, the secret itself comes out.
Clue = Data.define(:text, :teller)

class Clue
  # [clues, problems] from a secret's steps.
  def self.parse(text)
    problems = []
    clues = text.to_s.lines.map(&:strip).reject(&:empty?).map do |line|
      words, teller = line.split("|", 2).map(&:strip)
      problems << "“#{line.truncate(40)}” needs words before the |" if words.blank?
      new(text: words.to_s, teller: teller.presence)
    end
    [ clues, problems ]
  end

  def self.list(text) = parse(text).first

  # How the table hears it: "Mara Vell says: …", or the clue itself.
  def to_s = teller ? "#{teller} says: #{text}" : text

  def question? = text.end_with?("?")
end
