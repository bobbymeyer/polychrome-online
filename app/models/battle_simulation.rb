# frozen_string_literal: true

# A fight played out many times before anyone plays it, for the GM
# balancing the game: some of the campaign's characters against some of the
# world's monsters, or against an encounter table (each run rolls its group,
# by weight, as the road does), from seeds 1 to runs (Battle::Forecast).
# Nothing is kept: no battle, no line in the log.
#
#   sim = BattleSimulation.new(campaign, character_ids: [1, 2], encounter: { "goblin" => 3 }, runs: 50)
#   sim.result # => { "runs", "wins", "rounds", "hp_left", "mp_left", "downed", "report" }
class BattleSimulation
  RUNS = 50
  # A long boss fight a hundred times over is a few seconds: the page waits for it.
  MAX_RUNS = 100

  attr_reader :campaign, :encounter, :table, :runs, :tactics

  # rested: everyone starts at their full HP and MP; else as they are now.
  def initialize(campaign, character_ids: [], encounter: {}, table: nil, runs: RUNS, tactics: "full", rested: true)
    @campaign = campaign
    @character_ids = Array(character_ids).compact_blank.map(&:to_i)
    @encounter = encounter.to_h.transform_keys(&:to_s).select { |slug, count| count.to_i.positive? && world.monsters.exists?(slug: slug) }
                          .transform_values { |count| count.to_i.clamp(1, 8) }
    @table = table
    @runs = runs.to_i.clamp(1, MAX_RUNS)
    @tactics = Battle::Forecast::TACTICS.include?(tactics) ? tactics : "full"
    @rested = rested
  end

  def world = campaign.world

  def rested? = @rested

  # Who fights: the characters picked, else everyone in the party.
  def characters
    @characters ||= @character_ids.any? ? campaign.characters.where(id: @character_ids).to_a : campaign.characters.to_a
  end

  def ready? = characters.any? && (encounter.any? || table.present?)

  def result
    @result ||= Battle::Forecast.run(states, tactics: tactics, report: true) if ready?
  end

  private

  # A state for each run. Only the dice differ between seeds (Battle::State.build), so each fight is built
  # once, from the books, and each run takes its own seed; the resolver never changes the state it's given.
  def states
    party = characters.map { |character| rested? ? character.battle_spec.except("hp", "mp") : character.battle_spec }
    built = Hash.new { |fights, monsters| fights[monsters] = world.battle(seed: 1, party: party, monsters: monsters) }
    (1..runs).map do |seed|
      monsters = table ? Pointcrawl::Encounters.weighted(Battle::Rng.new(seed), table.entries) : encounter
      built[monsters].merge("seed" => seed, "rng" => Battle::Rng.seed_state(seed))
    end
  end
end
