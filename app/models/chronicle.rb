# frozen_string_literal: true

# A world's pocket history (Generators::History), run over its atlas before
# play, and written into the canon the GM already edits: a History page and
# a page per family in the codex, the living heads of the families in the
# cast, a past on every place in the atlas, and each feud still running as
# a front, with what really happened as its secrets.
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

  def generated
    @generated ||= Generators::History.generate(seed: seed, places: places, years: years, families: kept,
                                                given_names: table_texts("names"), family_names: table_texts("families"))
  end

  def places
    world.world_places.order(:id).map { |p| { "key" => key_for(p), "name" => p.name, "kind" => p.kind } }
  end

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

  # --- into the canon ---------------------------------------------------------

  # Returns what it wrote: { codex:, figures:, places:, fronts: } counts.
  def write!
    counts = Hash.new(0)
    world.transaction do
      take_out!(record: false)
      write_codex(counts)
      write_figures(counts)
      write_places(counts)
      write_fronts(counts)
      save!({ "written" => seed, "written_at" => Time.current.iso8601 })
    end
    counts
  end

  # What the history wrote, less what the GM has changed since.
  def take_out!(record: true)
    world.transaction do
      [ world.codex_entries, world.world_figures, world.world_fronts ].each do |scope|
        scope.where.not(history_key: nil).find_each { |row| row.destroy! unless changed?(row) }
      end
      world.world_places.find_each do |place|
        place.update!(past: {}) if place.past.present? && !Past.new(place.past).edited?
      end
      save!(history.except("written", "written_at"), replace: true) if record
    end
  end

  # Changed by the GM since it was written (saved from its form, or given
  # portraits): theirs now.
  def changed?(row)
    row.edited? || (row.respond_to?(:portraits) && row.portraits.exists?)
  end

  def family(key) = generated["families"].find { |f| f["key"] == key }
  def family_named(name) = generated["families"].find { |f| f["name"] == name }

  # "95 years ago: Osric Vell founded Tule."
  def line(event) = "#{Generators::History.ago(event['ago']).upcase_first}: #{event['text']}"
  def truth_line(event) = "#{Generators::History.ago(event['ago']).upcase_first}: #{event['truth']}"

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

  def taken?(scope, attribute, value)
    scope.exists?(attribute => value)
  end

  def write_codex(counts)
    events = generated["events"]
    unless taken?(world.codex_entries, :title, history_title)
      world.codex_entries.create!(title: history_title, category: "History", history_key: "history",
                                  body: events.map { |e| line(e) }.join("\n\n"),
                                  gm_notes: events.select { |e| e["truth"] }.map { |e| truth_line(e) }.join("\n\n").presence)
      counts[:codex] += 1
    end
    generated["families"].each do |f|
      title = "The #{f['name']} family"
      next if taken?(world.codex_entries, :title, title)

      mine = events.select { |e| e["families"].include?(f["key"]) }
      world.codex_entries.create!(title: title, category: "People", history_key: f["key"],
                                  body: family_body(f, mine), gm_notes: mine.select { |e| e["truth"] }.map { |e| truth_line(e) }.join("\n\n").presence)
      counts[:codex] += 1
    end
  end

  def history_title
    "The last #{years} years"
  end

  def family_body(f, events)
    plural = Generators::History.plural(f["name"])
    seat = f["seat"] && place_for(f["seat"])&.name
    heads = f["lineage"].map do |head|
      span = [ head["from"], head["to"] ].compact.map { |y| y.zero? ? "now" : y }.join("–")
      "#{head['name']} (#{span} years ago#{", #{head['fate']}" if head['fate'] && head['fate'] != 'old age'})"
    end
    grudges = f["grudges"].map { |g| "The #{plural} have not forgiven the #{Generators::History.plural(family(g['against'])&.dig('name'))} for #{g['why'].sub(/\A./, &:downcase)}." }
    [ "#{f['trade'].to_s.capitalize.sub(/man\z/, 'men').sub(/(?<!men)\z/, 's')}#{" of #{seat}" if seat}.#{" They left the region #{Generators::History.ago(f['gone'])}." if f['gone']}",
      ("#{f['head']} is the head of the house#{"; #{f['heir']} is the heir" if f['heir']}." if f["head"]),
      "Heads of the house: #{heads.to_sentence}.",
      *grudges,
      *events.map { |e| line(e) } ].compact.join("\n\n")
  end

  def write_figures(counts)
    generated["families"].each do |f|
      next unless f["head"]
      next if taken?(world.world_figures, :name, f["head"])

      grudge = f["grudges"].last
      against = grudge && family(grudge["against"])
      seat = f["seat"] && place_for(f["seat"])
      world.world_figures.create!(name: f["head"], title: "Head of the #{f['name']} family, #{f['trade']}", history_key: f["key"],
                                  world_place: seat,
                                  blurb: [ "Keeps the #{Generators::History.plural(f['name'])}' #{f['trade']} trade#{" in #{seat.name}" if seat}.",
                                           ("Won't sit at a table with a #{against['name']}." if against) ].compact.join(" "),
                                  description: generated["events"].select { |e| e["truth"]&.include?(f["head"]) }.map { |e| truth_line(e) }.join("\n\n").presence)
      counts[:figures] += 1
    end
  end

  def write_places(counts)
    generated["places"].each do |key, past|
      place = place_for(key) or next
      next if Past.new(place.past).edited?

      kept = past.except("key", "name", "kind")
      next if kept.empty?

      place.update!(past: kept)
      counts[:places] += 1
    end
  end

  def write_fronts(counts)
    generated["feuds"].each do |feud|
      a, b = feud["families"].map { |key| family(key) }
      name = "The #{a['name']}–#{b['name']} feud"
      next if taken?(world.world_fronts, :name, name)

      secrets = generated["events"].select { |e| e["truth"] && e["families"].intersect?(feud["families"]) }.map do |e|
        figure = world.world_figures.find_by(name: [ a["head"], b["head"] ].compact.find { |n| e["truth"].include?(n) })
        { "body" => e["truth"], "place_id" => e["places"].filter_map { |k| place_for(k)&.id }.first, "figure_id" => figure&.id }
      end
      seat = [ a, b ].filter_map { |f| f["seat"] && place_for(f["seat"]) }.first
      world.world_fronts.create!(
        name: name, history_key: "feud-#{feud['families'].join('-')}",
        description: "#{Generators::History.plural(a['name'])} and #{Generators::History.plural(b['name'])}, at odds since #{feud['cause']} (#{Generators::History.ago(feud['since'])}).",
        clocks: [ { "name" => "The #{a['name']}–#{b['name']} feud comes to blood", "segments" => 6, "triggers" => [ "now_and_then" ],
                    "full_line" => "The feud comes to blood: a #{b['name']} is found dead, and every #{a['name']} is carrying a knife.",
                    "place_id" => seat&.id } ],
        secrets: secrets
      )
      counts[:fronts] += 1
    end
  end
end
