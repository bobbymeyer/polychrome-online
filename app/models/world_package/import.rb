# frozen_string_literal: true

# A world package made into a new world (WorldPackage), owned by whoever
# imported it: its setting, its music, its books, then its canon, each
# pointing at the new world's own. All of it or none of it.
#
# The file is someone else's: only the fields the format names are read,
# each into the column it's for, and everything is validated as if an
# author had typed it.
module WorldPackage
  class Import
    attr_reader :archive, :owner

    include PackageReading

    def initialize(source, owner:, name: nil, slug: nil)
      @archive = source.is_a?(PackageArchive) ? source : PackageArchive.read(source, format: FORMAT)
      @owner = owner
      @name = name.presence
      @slug = slug.presence
      @refs = {}
      @tracks = {}
    end

    def data = archive.data

    def run!
      World.transaction do
        world = World.create!(setting.merge("name" => name, "slug" => free_slug, "owner" => owner))
        tracks!(world)
        PackageBooks.add!(world, books, archive, from: name)
        canon!(world)
        world.update!(history: places_renamed(hash(hash(data["world"])["history"])))
        world
      end
    rescue ActiveRecord::RecordInvalid => e
      raise Refusal, "#{name} couldn't be imported: #{e.record.class.model_name.human} #{e.record.try(:name)}: #{e.record.errors.full_messages.to_sentence}."
    end

    def name = @name || text(data["name"]).presence || "Imported world"

    private

    # What each of the setting's fields holds: a field in another shape is left at the new world's default.
    SHAPES = {
      "description" => String, "voice" => String, "avoid" => String, "lines" => String, "veils" => String,
      "damage_types" => Array, "skills" => Array, "origins" => Array,
      "terrain_types" => Hash, "terms" => Hash, "calendar" => Hash, "battle_rules" => Hash
    }.freeze

    def setting
      given = hash(data["world"])
      SHAPES.select { |field, shape| given[field].is_a?(shape) }.to_h { |field, _| [ field, given[field] ] }
    end

    # The address asked for, or the package's, or the name's; with a number
    # on the end if a world here has it already.
    def free_slug
      base = (@slug || text(data["slug"]) || name).to_s.parameterize(separator: "_").sub(/\A[^a-z]+/, "").presence || "world"
      return base unless World.exists?(slug: base)

      (2..).lazy.map { |n| "#{base}_#{n}" }.find { |slug| !World.exists?(slug: slug) }
    end

    def tracks!(world)
      records(data["tracks"]).each do |row|
        track = world.tracks.new(name: text(row["name"]), scene: text(row["scene"]), source: text(row["source"]) || "upload",
                                 url: text(row["url"]), position: int(row["position"]).to_i)
        archive.attach(track.audio, row["audio"], kind: "audio")
        track.save!
        old = row["ref"].to_s[/\Atrack-(\d+)\z/, 1]
        @tracks["track:#{old}"] = "track:#{track.id}" if old
      end
    end

    # The books as written, a monster's own music pointed at this world's copy of the track.
    def books
      hash(data["books"]).to_h do |kind, rows|
        [ kind, records(rows).map { |row| row["music"] ? row.merge("music" => @tracks[row["music"]]) : row } ]
      end
    end

    def canon!(world)
      maps = records(data["maps"])
      maps.each do |row|
        map = world.world_maps.create!(name: text(row["name"]), x: int(row["x"]), y: int(row["y"]), description: text(row["description"]))
        archive.attach(map.image, row["image"])
        @refs[row["ref"]] = map
      end
      maps.each { |row| @refs[row["ref"]].update!(parent: @refs[row["parent"]]) if @refs[row["parent"]].is_a?(WorldMap) }
      records(data["map_links"]).each do |row|
        from, to = @refs[row["from"]], @refs[row["to"]]
        world.world_map_links.create!(from_map: from, to_map: to, direction: text(row["direction"])) if from.is_a?(WorldMap) && to.is_a?(WorldMap)
      end

      records(data["places"]).each do |row|
        map = @refs[row["map"]]
        @refs[row["ref"]] = world.world_places.create!(
          name: text(row["name"]), kind: text(row["kind"]), x: int(row["x"]).to_i, y: int(row["y"]).to_i, known: row["known"] == true,
          description: text(row["description"]), notes: text(row["notes"]), seed: int(row["seed"]), past: hash(row["past"]),
          lead: text(row["lead"]), activities: text(row["activities"]), night_line: text(row["night_line"]),
          location_template: world.location_templates.find_by(slug: row["template"]), world_map: (map if map.is_a?(WorldMap))
        )
      end
      records(data["routes"]).each do |row|
        from, to = @refs[row["from"]], @refs[row["to"]]
        next unless from.is_a?(WorldPlace) && to.is_a?(WorldPlace)

        world.world_routes.create!(from_place: from, to_place: to, state: text(row["state"]) || "open", duration: int(row["duration"]) || 1,
                                   travel_event: text(row["travel_event"]), waypoints: list(row["waypoints"]),
                                   encounter_table: world.encounter_tables.find_by(slug: row["encounters"]))
      end

      records(data["figures"]).each do |row|
        place = @refs[row["place"]]
        figure = world.world_figures.create!(name: text(row["name"]), title: text(row["title"]), blurb: text(row["blurb"]),
                                             description: text(row["description"]), colour: text(row["colour"]),
                                             history_key: place_key(text(row["history_key"])), edited: row["edited"] == true,
                                             monster: world.monsters.find_by(slug: row["monster"]), world_place: (place if place.is_a?(WorldPlace)))
        hash(row["portraits"]).each do |expression, file|
          archive.attach(figure.portraits.create!(expression: expression).image, file) if Portrait::EXPRESSIONS.include?(expression)
        end
        archive.attach(figure.create_sprite!.image, row["sprite"]) if row["sprite"].present?
        @refs[row["ref"]] = figure
      end

      records(data["codex"]).each do |row|
        world.codex_entries.create!(title: text(row["title"]), category: text(row["category"]), body: text(row["body"]), gm_notes: text(row["gm_notes"]),
                                    public: row["public"] != false, history_key: place_key(text(row["history_key"])), edited: row["edited"] == true)
      end

      records(data["fronts"]).each do |row|
        id = ->(ref, kind) { (record = @refs[ref]).is_a?(kind) ? record.id : nil }
        clocks = records(row["clocks"]).map do |clock|
          clock.slice(*%w[name segments triggers full_line public mode_name mode_line mode_description impulse portents])
                     .merge("place_id" => id.(clock["place"], WorldPlace), "source_id" => id.(clock["source"], WorldPlace))
        end
        secrets = records(row["secrets"]).map do |secret|
          { "body" => text(secret["body"]), "steps" => text(secret["steps"]), "key" => text(secret["key"]),
            "place_id" => id.(secret["place"], WorldPlace), "figure_id" => id.(secret["figure"], WorldFigure) }
        end
        world.world_fronts.create!(name: text(row["name"]), description: text(row["description"]), history_key: place_key(text(row["history_key"])),
                                   edited: row["edited"] == true, clocks: clocks, secrets: secrets)
      end
    end

    # The history names its places "place-<id>" (Chronicle#key_for): the
    # package's ids, which are this world's places now.
    def place_key(value)
      old = value.to_s[/\Aplace-(\d+)\z/, 1] or return value
      place = @refs["world-place-#{old}"]
      place.is_a?(WorldPlace) ? "place-#{place.id}" : value
    end

    def places_renamed(value)
      case value
      when Hash then value.to_h { |key, item| [ place_key(key), places_renamed(item) ] }
      when Array then value.map { |item| places_renamed(item) }
      when String then place_key(value)
      else value
      end
    end
  end
end
