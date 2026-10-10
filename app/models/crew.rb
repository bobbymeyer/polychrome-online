# frozen_string_literal: true

# A crewed fight (the Giant Battle): the party doesn't fight as themselves
# but crews one great body, each character at a station, a Bestiary entry
# (its stats, moves and types) that they command as they would themselves.
# A station's damage is the body's, not the character's: the settlement
# leaves their own HP alone.
#
# The plan, as a room's decision or a scene's fight writes it:
#
#   { "stations" => { "courtsword" => "station_blade", ... }, # by job
#     "default"  => "station_blade",                          # a job the plan doesn't name
#     "wearers"  => [ { "npc" => "The Swordsman", "station" => "station_blade" }, ... ],
#     "seats"    => 7,    # masks: how many stations are crewed in all
#     "half_below" => 4 } # fewer players than this: each crews two
#
# With fewer players than seats, the cast's wearers crew stations too, in
# order, on their own (guests under the station's script). With fewer than
# half_below, each player wears two masks: two systems in one body, with a
# second station nobody else crews, its moves, the larger HP and MP and
# half the other's, the better of each other stat, and two goes a round
# (haste, all battle).
class Crew
  SEATS = 7
  HALF_BELOW = 4

  attr_reader :world, :characters, :plan, :npcs

  def initialize(world, characters, plan, npcs: Npc.none)
    @world = world
    @characters = characters
    @plan = plan.to_h.deep_stringify_keys
    @npcs = npcs
  end

  def self.plan?(plan) = plan.is_a?(Hash) && plan["stations"].is_a?(Hash)

  # { character => station } for everyone in the party.
  def stations
    @stations ||= characters.index_with { |character| form(plan.fetch("stations", {})[character.job.slug] || plan["default"]) }.compact
  end

  # The engine's specs for the party: each character at their station.
  def party_specs
    seconds = second_stations
    characters.map do |character|
      station = stations[character] or next character.battle_spec
      also = seconds[character]
      spec = station.to_engine.slice("stats", "types", "affinities", "status_immune", "abilities")
      spec = both(spec, also) if also
      spec.merge("id" => character.battle_unit_id, "name" => "#{character.name} · #{[ station.name, also&.name ].compact.join(' & ')}",
                 "level" => character.level, "image" => { "book" => "jobs", "slug" => character.job.slug })
    end
  end

  # The cast's wearers who crew the stations nobody at the table does,
  # as specs for guests under their station's script.
  def wearer_specs
    wearers.map do |npc, station|
      station.to_engine.except("count", "rewards", "drops", "boss", "phases", "music")
             .merge("id" => "crew_npc_#{npc.id}", "name" => "#{npc.name} · #{station.name}", "image" => { "book" => "npcs", "slug" => npc.id.to_s })
    end
  end

  # Two masks, two systems: both stations' moves, the larger pool and half the other, and the better of each other stat.
  POOLED = %w[max_hp max_mp].freeze
  ALL_BATTLE = 99

  def both(spec, also)
    other = also.stats
    stats = spec["stats"].to_h do |stat, value|
      pair = [ value, other.fetch(stat, 0) ]
      [ stat, POOLED.include?(stat) ? [ pair.max + pair.min / 2, Stats::CAPS.fetch(stat) ].min : pair.max ]
    end
    spec.merge("stats" => stats, "abilities" => (spec["abilities"] + also.ability_slugs).uniq)
  end

  # Who wears two masks: they go twice a round, all battle (BattleRecord.start! puts the haste on).
  def two_masks = second_stations.keys.map(&:battle_unit_id)

  # The units the settlement leaves alone: everyone at a station.
  def crewing = stations.to_h { |character, station| [ character.battle_unit_id, station.slug ] }

  private

  # The cast's wearers who join: [[npc, station], ...], as many as the seats left open.
  def wearers
    @wearers ||= Array(plan["wearers"]).filter_map do |row|
      npc = npcs.find_by(name: row["npc"]) or next
      station = form(row["station"]) or next
      [ npc, station ]
    end.first([ seats - worn, 0 ].max)
  end

  def seats = plan.fetch("seats", SEATS).to_i
  def half? = characters.size < plan.fetch("half_below", HALF_BELOW).to_i
  def worn = characters.size * (half? ? 2 : 1)

  # Fewer players than half_below: each also crews a station nobody else
  # does, in the order the plan lists them.
  def second_stations
    return {} unless half?
    return @second_stations if @second_stations

    taken = (stations.values + wearers.map(&:last)).map(&:slug)
    free = plan.fetch("stations", {}).values.uniq.reject { |slug| taken.include?(slug) }.filter_map { |slug| form(slug) }
    @second_stations = stations.keys.zip(free).to_h.compact
  end

  def form(slug)
    @forms ||= {}
    @forms[slug] ||= world.monsters.find_by(slug: slug) if slug.present?
  end
end
