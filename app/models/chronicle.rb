# frozen_string_literal: true

# A world's pocket history (Generators::History), run over its atlas before
# play, and written into the canon the GM already edits: a History page and
# a page per family in the codex, the living heads of the families in the
# cast, a past on every place in the atlas, and each feud still running as
# a front, with what really happened as its secrets.
#
# Rolling it (and keeping families through rerolls) is here; writing it
# into the canon and taking it back out is Chronicle::Canon, and the pages
# it writes are templates (app/views/chronicles/).
#
# The world keeps only the seed, the span and the families the GM has
# kept (world.history); the rest is rolled again from those, so rerolling
# is a new seed and the kept families stay. Writing it in again replaces
# what it wrote before, except what the GM has changed since: that's
# theirs now.
#
#   world.history: { "seed" => 1234, "years" => 100, "families" => [{ "name", "trade", "seat" }],
#                    "written" => 1234, "written_at" => "..." }
class Chronicle
  include Canon

  YEARS = 40..300

  attr_reader :world

  def initialize(world)
    @world = world
  end

  def history = world.history.to_h
  def seed = history["seed"] || default_seed
  def years = (history["years"] || 100).to_i.clamp(YEARS.min, YEARS.max)
  def kept = Array(history["families"])
  def written? = history.key?("written")
  def written_seed = history["written"]

  # The events as they were written in: [{ "ago", "kind", "text", "truth", "places" => ["place-12"] }].
  def written_events = Array(history["events"])

  # The atlas place an event's key names ("place-12").
  def self.place_id(key) = key.to_s.delete_prefix("place-").to_i

  def generated
    @generated ||= Generators::History.generate(seed: seed, places: places, years: years, families: kept,
                                                given_names: table_texts("names"), family_names: table_texts("families"), lore: world.lore)
  end

  # The places the history happens in: not those whose past the GM wrote
  # themselves (kept), so it never tells a different story about them.
  def places
    world.world_places.order(:id).reject { |p| kept_past?(p) }.map { |p| { "key" => key_for(p), "name" => p.name, "kind" => p.kind } }
  end

  def kept_places = world.world_places.order(:name).select { |p| kept_past?(p) }

  def kept_past?(place) = Past.new(place.past).edited?

  def key_for(place) = "place-#{place.id}"
  def place_for(key) = world_places_by_key[key]

  # --- the GM's controls --------------------------------------------------------

  def reroll!
    save!({ "seed" => Location.new_seed })
  end

  def set_years!(value)
    save!({ "years" => value.to_i.clamp(YEARS.min, YEARS.max) })
  end

  # Keep a family through rerolls: its name, trade and seat.
  def keep!(family_key)
    family = generated["families"].find { |f| f["key"] == family_key } or raise Refusal, "No family called #{family_key}"
    return if kept.any? { |f| f["name"] == family["name"] }

    save!({ "families" => kept + [ family.slice("name", "trade", "seat").compact ] })
  end

  def let_go!(name)
    save!({ "families" => kept.reject { |f| f["name"] == name } })
  end

  def kept?(family) = kept.any? { |f| f["name"] == family["name"] }

  def family(key) = generated["families"].find { |f| f["key"] == key }

  private

  def default_seed
    world.id.to_i * 7919 % 2**31
  end

  def save!(changes, replace: false)
    world.update!(history: replace ? changes : history.merge(changes))
    @generated = nil
  end

  def table_texts(kind)
    world.generator_tables.of_kind(kind).flat_map { |t| t.entries.map { |e| e["text"] } }.compact_blank
  end

  def world_places_by_key
    @world_places_by_key ||= world.world_places.index_by { |p| key_for(p) }
  end
end
