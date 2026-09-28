# frozen_string_literal: true

# Writing the history into the canon the GM already edits, and taking it
# back out: a History page and a page per family in the codex, the living
# heads in the cast, a past on every atlas place, and every feud still
# running as a front, with what really happened as its secrets. Anything
# the GM has changed since it was written is theirs, and stays.
module Chronicle::Canon
  # Returns what it wrote: { codex:, figures:, places:, fronts: } counts.
  def write!
    counts = Hash.new(0)
    world.transaction do
      take_out!(record: false)
      write_codex(counts)
      write_figures(counts)
      write_places(counts)
      write_fronts(counts)
      # Kept as written, for the legends: the atlas can change after.
      save!({ "written" => seed, "written_at" => Time.current.iso8601, "events" => generated["events"] })
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
      save!(history.except("written", "written_at", "events"), replace: true) if record
    end
  end

  # Changed by the GM since it was written (saved from its form, or given
  # portraits): theirs now.
  def changed?(row)
    row.edited? || (row.respond_to?(:portraits) && row.portraits.exists?)
  end

  private

  def taken?(scope, attribute, value)
    scope.exists?(attribute => value)
  end

  # A codex page's words, from its template (app/views/chronicles/).
  def page(template, **locals)
    ApplicationController.render(partial: "chronicles/#{template}", formats: [ :text ], locals: locals.merge(chronicle: self)).strip
  end

  def truths(events) = events.select { |e| e["truth"] }.map { |e| "#{Generators::History.ago(e['ago']).upcase_first}: #{e['truth']}" }.join("\n\n").presence

  def write_codex(counts)
    events = generated["events"]
    title = "The last #{years} years"
    unless taken?(world.codex_entries, :title, title)
      world.codex_entries.create!(title: title, category: "History", history_key: "history",
                                  body: page("history", events: events), gm_notes: truths(events))
      counts[:codex] += 1
    end
    generated["families"].each do |f|
      title = "The #{f['name']} family"
      next if taken?(world.codex_entries, :title, title)

      mine = events.select { |e| e["families"].include?(f["key"]) }
      world.codex_entries.create!(title: title, category: "People", history_key: f["key"],
                                  body: page("family", family: f, events: mine, seat: f["seat"] && place_for(f["seat"])),
                                  gm_notes: truths(mine))
      counts[:codex] += 1
    end
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
                                  description: truths(generated["events"].select { |e| e["truth"]&.include?(f["head"]) }))
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
