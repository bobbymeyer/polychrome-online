# frozen_string_literal: true

# Duels (docs/ODA.md): a character against someone the GM plays, outside
# battle: three swings each on a meter (Duel, DuelMeter). Someone at the
# table can be challenged by a cast member or a Bestiary entry: the
# challenge waits on the table until the character's player answers.
# Accepting starts the duel; refusing makes them a coward
# (Character::Courage), until they fight and win another. A character's own
# challenge, the GM accepts for whoever they called out and the duel starts
# at once.
#
# The challenge waiting for an answer is campaigns.challenge:
#   { "character_id", "npc_id" | "monster", "line" }
module Campaign::Duels
  extend ActiveSupport::Concern

  # The duel the table is watching: under way, or just ended and not yet put away.
  def current_duel = duels.shown.order(:id).last

  # The people the GM can put up in a duel: the cast members who fight
  # as a Bestiary entry and are still at large.
  def duellists
    npcs.at_large.where.not(monster_id: nil).order(:name)
  end

  # Someone the GM plays calls a character out. They answer at the table.
  def challenge!(character:, npc: nil, monster: nil, line: nil)
    raise Refusal, "A battle is on: the challenge can wait until it's over" if battle_on?
    raise Refusal, "A duel is on: one at a time" if current_duel&.on?
    raise Refusal, "#{character.name} can't stand to fight a duel" unless character.conscious?
    raise Refusal, "Someone has to issue the challenge" unless npc || monster

    update!(challenge: { "character_id" => character.id, "npc_id" => npc&.id, "monster" => monster&.slug,
                         "line" => line.to_s.strip.presence }.compact)
    narrate("#{challenger_name} challenges #{character.name} to a duel!#{" “#{challenge['line']}”" if challenge['line']}")
    table_changed
  end

  # A character calls someone out, and the GM has them accept: the duel is on.
  def call_out!(character:, npc: nil, monster: nil)
    raise Refusal, "Someone has to answer the challenge" unless npc || monster

    narrate("#{character.name} challenges #{npc&.name || monster.name} to a duel, and the challenge is taken.")
    duel!(character: character, npc: npc, monster: monster)
  end

  def challenged_character
    challenge && characters.find_by(id: challenge["character_id"])
  end

  def challenger_npc = challenge && challenge["npc_id"] && npcs.find_by(id: challenge["npc_id"])
  def challenger_monster = challenge && challenge["monster"] && world.monsters.find_by(slug: challenge["monster"])

  def challenger_name
    challenger_npc&.name || challenger_monster&.name || "Someone"
  end

  # The challenged character's answer: the duel, or a coward.
  def answer_challenge!(accept:)
    character = challenged_character or raise Refusal, "Nobody has been challenged"
    npc = challenger_npc
    monster = challenger_monster
    update!(challenge: nil)
    if accept
      narrate("#{character.name} accepts.")
      duel!(character: character, npc: npc, monster: monster)
    else
      character.refuse_duel!(npc&.name || monster&.name || "someone")
      table_changed
      nil
    end
  end

  # The GM takes the challenge back: nobody answered, and nobody is shamed.
  def withdraw_challenge!
    return unless challenge

    name = challenger_name
    update!(challenge: nil)
    narrate("#{name} lets the challenge go.")
    table_changed
  end

  def duel!(character:, npc: nil, monster: nil)
    raise Refusal, "#{character.name} can't stand to fight a duel" unless character.conscious?
    raise Refusal, "A duel is on: one at a time" if current_duel&.on?

    current_duel&.close!
    duel = duels.create!(character: character, npc: npc, opponent_name: npc&.name || monster.name, seed: Random.new_seed % 2**31)
    narrate("The duel: #{character.name} and #{duel.opponent_name}. Three swings each; the best wins.")
    table_changed
    duel
  end

  # A coward in the party sets every price they're asked (Location::Town#price_here).
  def cowards = characters.where(coward: true)
end
