# frozen_string_literal: true

# A Bestiary entry tried against a party before anyone has to meet it: a
# level-5 party of the world's archetypes in starting gear, some of the
# creature, everyone on their default command, through the engine. What
# the seed specs do for every monster, on the entry's page for one. Pure
# over the books: nothing is saved.
class Monster::Trial
  BASE = { max_hp: 150, max_mp: 30, str: 12, mag: 12, vit: 12, spr: 12, agi: 12 }.freeze
  ROUNDS = 60

  attr_reader :monster, :count, :party, :state

  def initialize(monster, count: 2, seed: monster.id)
    @monster = monster
    @count = count
    @party = build_party(monster.world)
    @state = monster.world.battle(seed: seed, party: @party, monsters: { monster.slug => count })
    ROUNDS.times do
      break unless @state["status"] == "input"

      @state, = Battle::Resolver.apply(@state, { type: "timeout" })
    end
  end

  def outcome = state["status"]
  def rounds = state["round"]
  def standing = BattleState.new(state).units.select(&:party?)
  def enemies = BattleState.new(state).units.select(&:enemy?)

  private

  # The first four archetypes with a shape of their own (not the plain,
  # unmodified starter), each in the cheapest piece it can wear per slot.
  def build_party(world)
    jobs = world.jobs.order(:name).reject { |job| job.stat_multipliers.empty? }.first(4)
    jobs = world.jobs.order(:name).first(4) if jobs.empty?
    items = world.items.select(&:equipment?)
    jobs.map do |job|
      gear = items.select { |item| job.equips?(item) }.group_by(&:slot).values.map { |pieces| pieces.min_by(&:price) }
      stats = Stats::Derivation.derive(base: BASE, job: job.to_derivation, equipment: gear.map(&:to_equipment), passives: job.passives)
      { id: job.slug, name: job.name, stats: stats, abilities: job.abilities.pluck(:slug) }.merge(job.battle_type)
    end
  end
end
