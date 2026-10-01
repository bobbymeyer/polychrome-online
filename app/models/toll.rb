# frozen_string_literal: true

# What a dungeon's costly way takes from the party (a fork: Generators::
# Dungeon), read from its row the way a thing to do's brackets are read
# (Pastime): what the table hears, then in brackets what it costs.
#
#   A sealed door that opens for coin in the slot. (pay 100)
#   Poison gas: it catches in every throat. (hurt 10)
#   A long climb. (2)
#   Loose rock: the noise carries. (ambush)
#   A rope bridge: someone must stay behind to hold it.
#
# In brackets, in any order: "pay 25" in the world's money; a number of
# parts of the day it takes; outcomes (Outcome), usually what takes (hurt,
# weary, ambush), though a way can give as well. A row with no brackets is
# a cost the GM plays out. Taken the first time the party goes that way
# (Location::Exploration).
Toll = Data.define(:words, :price, :takes, :outcomes)

class Toll
  BRACKETS = /\s*\((?<inside>[^)]*)\)\s*\z/

  # [toll, problems]
  def self.read(text)
    text = text.to_s.strip
    match = BRACKETS.match(text)
    return [ new(words: text, price: 0, takes: 0, outcomes: []), [] ] unless match

    price = 0
    takes = 0
    outcomes = []
    problems = []
    match[:inside].split(%r{\s*[/,]\s*}).map(&:strip).reject(&:empty?).each do |word|
      if word.match?(/\A\d+\z/) then takes = word.to_i
      elsif (paid = word[/\Apay\s+(\d+)\z/i, 1]) then price = paid.to_i
      elsif (outcome = Outcome.parse(word)) then outcomes << outcome
      else problems << "“#{word}” isn't a price (pay 100), a number of parts of the day, or an outcome (hurt 10, weary 25, ambush…)"
      end
    end
    [ new(words: text.sub(BRACKETS, ""), price: price, takes: takes, outcomes: outcomes), problems ]
  end

  def self.of(text) = read(text).first

  def free? = price.zero? && takes.zero? && outcomes.empty?

  # "100 gil, 10% HP, part of the day": what it costs, for the ways on.
  def describe(campaign)
    [ (campaign.money(price) if price.positive?),
      *outcomes.map { |o| o.kind == "ambush" ? "a fight" : o.describe(campaign.world).sub(/\AEveryone standing loses /, "").downcase_first },
      (takes == 1 ? "part of the day" : "#{takes} parts of the day" if takes.positive?) ].compact.join(", ")
  end
end
