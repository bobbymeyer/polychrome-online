# frozen_string_literal: true

# A Bestiary entry tried against a party before anyone has to meet it: a
# level-5 party of the world's archetypes in starting gear, some of the
# creature, everyone on their default command, through the engine. What
# the seed specs do for every monster, on the entry's page for one. Pure
# over the books: nothing is saved.
#
# A boss is a sequence of moments, so the trial keeps them: every move the
# creature used and how often, who fell and when, what it inflicted. And
# one roll is one roll: ten more from here say how it tends to go.
class Monster::Trial
  BASE = { max_hp: 150, max_mp: 30, str: 12, mag: 12, vit: 12, spr: 12, agi: 12 }.freeze
  ROUNDS = 60
  ROLLS = 10

  attr_reader :monster, :count, :party, :state, :events

  def initialize(monster, count: nil, seed: monster.id)
    @monster = monster
    @count = count || (monster.boss? ? 1 : 2) # a boss comes alone
    @party = build_party(monster.world)
    @seed = seed
    @state = battle(seed)
    @events = []
    ROUNDS.times do
      break unless @state["status"] == "input"

      @state, happened = Battle::Resolver.apply(@state, { type: "timeout" })
      @events.concat(happened)
    end
  end

  def outcome = state["status"]
  def rounds = state["round"]
  def standing = BattleState.new(state).units.select(&:party?)
  def enemies = BattleState.new(state).units.select(&:enemy?)

  # Each move the creatures used, with how many times: [["Fire", 3], ["Attack", 2]]. adds: what the
  # creatures they called did instead.
  def moves(adds: false) = tally_moves(adds ? add_ids : own_ids)

  # What it said (its telegraphs, its reactions' and phases' lines), with how many times.
  def said
    events.filter_map { |e| e["line"] if %w[says].include?(e["type"]) && own_ids.include?(e["actor"]) }.tally.to_a
  end

  # Its reactions to blows of one type: they never fire here, where the party only attacks.
  def untried_counters
    monster.ai_script.select { |rule| rule["when"] == "hit" && rule["by"] }.map { |rule| rule["by"] }.uniq
  end

  # Who fell, and in which round: [["Knight", 7]].
  def fallen
    round = 0
    events.filter_map do |e|
      round = e["round"] if e["type"] == "round_start"
      [ unit_name(e["target"]), round ] if e["type"] == "ko" && party_ids.include?(e["target"])
    end
  end

  # The forms it took, and in which round: [["Crystal Wyrm, Unbound", 6]].
  def became
    round = 0
    events.filter_map do |e|
      round = e["round"] if e["type"] == "round_start"
      [ e["name"], round ] if e["type"] == "phase"
    end
  end

  # What the creatures put on the party, with how many times: [["Poison", 2]].
  def inflicted
    events.select { |e| e["type"] == "status_applied" && party_ids.include?(e["target"]) }
          .map { |e| e["status"].to_s.humanize }.tally.sort_by { |name, n| [ -n, name ] }
  end

  # Ten more rolls from this seed, the same way (Battle::Forecast's floor): how it tends to go.
  def forecast
    @forecast ||= Battle::Forecast.run(ROLLS.times.map { |i| battle(@seed + 1 + i) })
  end

  private

  def tally_moves(ids)
    events.filter_map do |e|
      next unless ids.include?(e["actor"])

      case e["type"]
      when "attack" then "Attack"
      when "cast" then e["name"] || names[e["ability"]] || e["ability"]
      end
    end.tally.sort_by { |name, n| [ -n, name ] }
  end

  def battle(seed) = monster.world.battle(seed: seed, party: party, monsters: { monster.slug => count })

  def enemy_ids = state["units"].select { |u| u["side"] == "enemy" }.map { |u| u["id"] }
  def own_ids = state["units"].select { |u| u["side"] == "enemy" && !u["summoned"] }.map { |u| u["id"] }
  def add_ids = state["units"].select { |u| u["side"] == "enemy" && u["summoned"] }.map { |u| u["id"] }
  def party_ids = state["units"].select { |u| u["side"] == "party" }.map { |u| u["id"] }
  def unit_name(id) = state["units"].find { |u| u["id"] == id }&.dig("name") || id
  def names = @names ||= monster.world.abilities.pluck(:slug, :name).to_h

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
