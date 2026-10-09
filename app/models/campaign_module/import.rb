# frozen_string_literal: true

# A module made into a new campaign (CampaignModule): its books' missing
# entries added to the world, then the prep, ref by ref, then the party
# sets out from where the module starts. All of it or none of it.
#
# The file is someone else's: only the fields the module format names are
# read, each into the column it's for, and everything is validated as if a
# GM had typed it.
module CampaignModule
  class Import
    attr_reader :archive, :world, :gm

    # can_add_books: whether whoever imports may add entries to the world's
    # books (Authorization#can_edit_world?). Without it, a module that
    # needs entries the world lacks is refused, and says which.
    def initialize(source, world:, gm:, can_add_books: true, name: nil)
      @archive = source.is_a?(Archive) ? source : Archive.read(source)
      @world = world
      @gm = gm
      @can_add_books = can_add_books
      @name = name.presence
      @refs = {}
    end

    def data = archive.data

    # The book entries the world doesn't have: { kind => [name, ...] }.
    def missing_books
      Books::KINDS.to_h do |kind, scope|
        slugs = rows(kind).map { |row| row["slug"].to_s }
        have = world.public_send(scope).where(slug: slugs).pluck(:slug)
        [ kind, rows(kind).reject { |row| have.include?(row["slug"].to_s) }.map { |row| row["name"] || row["slug"] } ]
      end.reject { |_, names| names.empty? }
    end

    def run!
      missing = missing_books.values_at(*SAID_FIRST).compact.flatten
      if missing.any? && !@can_add_books
        raise Refusal, "#{data['name']} needs #{missing.size} entries #{world.name}'s books don't have (#{missing.first(6).join(', ')}" \
                       "#{', …' if missing.size > 6}), and only the world's editors can add them."
      end

      Campaign.transaction do
        add_books!
        campaign = world.campaigns.create!(name: @name || data["name"].presence || "Imported campaign", gm: gm,
                                           lines: data["lines"], veils: data["veils"], open_jobs: open_jobs)
        build!(campaign)
        campaign
      end
    rescue ActiveRecord::RecordInvalid => e
      raise Refusal, "The module couldn't be imported: #{e.record.class.model_name.human} #{e.record.try(:name)}: #{e.record.errors.full_messages.to_sentence}."
    end

    # Which missing entries a refusal names first: the ones a GM would recognise.
    SAID_FIRST = %w[monsters items location_templates encounter_tables generator_tables abilities].freeze

    private

    def rows(kind) = Array(data.dig("books", kind)).select { |row| row.is_a?(Hash) && row["slug"].present? }

    def text(value) = value.is_a?(String) ? value : nil
    def int(value) = JsonCasting.integer(value)
    def list(value) = value.is_a?(Array) ? value : []
    def hash(value) = value.is_a?(Hash) ? value : {}

    # --- the books ------------------------------------------------------------------

    # The entries the world lacks, saved as their references allow: a move
    # that summons a creature after the creature, a monster after its moves
    # and forms. Pass after pass until nothing more will save.
    def add_books!
      pending = Books::KINDS.flat_map do |kind, scope|
        have = world.public_send(scope).pluck(:slug)
        rows(kind).reject { |row| have.include?(row["slug"]) }.map { |row| [ kind, scope, row ] }
      end
      loop do
        saved = pending.select { |kind, scope, row| save_entry(kind, scope, row) }
        pending -= saved
        break if pending.empty? || saved.empty?
      end
      return if pending.empty?

      problems = pending.map do |_, scope, row|
        entry = build_entry(scope, row)
        entry.valid?
        "#{entry.name || row['slug']}: #{entry.errors.full_messages.to_sentence}"
      end
      raise Refusal, "#{world.name} can't take some of the module's book entries: #{problems.first(5).join('; ')}."
    end

    def save_entry(_kind, scope, row)
      entry = build_entry(scope, row)
      return false unless entry.save

      attach(entry.image, row["image"])
      true
    end

    def build_entry(scope, row)
      model = world.public_send(scope)
      columns = model.klass.column_names - Books::SKIP
      attrs = row.slice(*columns)
      attrs["encounter_table"] = world.encounter_tables.find_by(slug: row["encounter_table"]) if model.klass == LocationTemplate && row["encounter_table"]
      model.new(attrs)
    end

    # --- the prep ---------------------------------------------------------------------

    def build!(campaign)
      maps!(campaign)
      places!(campaign)
      roads!(campaign)
      cast!(campaign)
      clocks!(campaign)
      secrets!(campaign)
      scenes!(campaign)
      list(data["flags"]).each { |flag| campaign.flags.create!(key: text(flag["key"]), value: text(flag["value"]).to_s, note: text(flag["note"])) }
      campaign.update!(current_node: @refs[data["start"]]) if @refs[data["start"]].is_a?(MapNode)
      campaign.set_out!(from_the_setting: false)
      list(data["rumours"]).each do |rumour|
        at = @refs[rumour["at"]] or next
        campaign.start_rumour!(text(rumour["body"]), at: at, about: @refs[rumour["about"]], sway: Rumour::SWAYS.include?(rumour["sway"]) ? rumour["sway"] : 0)
      end
    end

    def maps!(campaign)
      maps = list(data["maps"])
      maps.each do |row|
        map = campaign.maps.create!(name: text(row["name"]).presence || "Map", x: int(row["x"]), y: int(row["y"]), description: text(row["description"]))
        attach(map.image, row["image"])
        @refs[row["ref"]] = map
      end
      maps.each { |row| @refs[row["ref"]].update!(parent: @refs[row["parent"]]) if @refs[row["parent"]].is_a?(Map) }
      list(data["map_links"]).each do |row|
        from, to = @refs[row["from"]], @refs[row["to"]]
        campaign.map_links.create!(from_map: from, to_map: to, direction: text(row["direction"])) if from.is_a?(Map) && to.is_a?(Map)
      end
    end

    def places!(campaign)
      list(data["places"]).each do |row|
        map = @refs[row["map"]]
        node = campaign.map_nodes.create!(name: text(row["name"]), kind: text(row["kind"]), x: int(row["x"]).to_i, y: int(row["y"]).to_i,
                                          visible: row["visible"] == true, map: (map if map.is_a?(Map)),
                                          description: text(row["description"]), notes: text(row["notes"]), activities: text(row["activities"]))
        @refs[row["ref"]] = node
        if (spot = hash(row["location"])).present?
          template = world.location_templates.find_by(slug: spot["template"])
          raise Refusal, "#{node.name} is rolled from a template #{world.name} doesn't have (#{spot['template']})." unless template

          location = campaign.locations.create!(location_template: template, seed: int(spot["seed"]), overrides: overrides(hash(spot["overrides"])))
          node.update!(location: location)
          @refs[spot["ref"]] = location
        end
        list(row["modes"]).each do |mode_row|
          mode = node.modes.create!(key: text(mode_row["key"]), name: text(mode_row["name"]), line: text(mode_row["line"]),
                                    description: text(mode_row["description"]), closed: list(mode_row["closed"]), times: list(mode_row["times"]),
                                    music: music(mode_row["music"]), activities: text(mode_row["activities"]),
                                    encounter_table: world.encounter_tables.find_by(slug: mode_row["encounters"]))
          @refs[mode_row["ref"]] = mode
          next unless mode_row["picture"].present? && node.location

          attach(node.location.mode_arts.create!(mode: mode).image, mode_row["picture"])
        end
      end
    end

    def roads!(campaign)
      list(data["roads"]).each do |row|
        from, to = @refs[row["from"]], @refs[row["to"]]
        next unless from.is_a?(MapNode) && to.is_a?(MapNode)

        campaign.map_edges.create!(from_node: from, to_node: to, state: text(row["state"]) || "open", duration: int(row["duration"]) || 1,
                                   travel_event: text(row["travel_event"]), waypoints: list(row["waypoints"]),
                                   encounter_table: world.encounter_tables.find_by(slug: row["encounters"]))
      end
    end

    def cast!(campaign)
      list(data["cast"]).each do |row|
        home = @refs[row["home"]]
        npc = campaign.npcs.create!(name: text(row["name"]), title: text(row["title"]), description: text(row["description"]), colour: text(row["colour"]),
                                    monster: world.monsters.find_by(slug: row["monster"]), location: (home.location if home.is_a?(MapNode)),
                                    location_key: text(row["location_key"]))
        hash(row["portraits"]).each do |expression, name|
          attach(npc.portraits.create!(expression: expression).image, name) if Portrait::EXPRESSIONS.include?(expression)
        end
        attach(npc.create_sprite!.image, row["sprite"]) if row["sprite"].present?
        @refs[row["ref"]] = npc
      end
    end

    def clocks!(campaign)
      list(data["clocks"]).each do |row|
        mode = @refs[row["mode"]]
        node = @refs[row["place"]]
        campaign.clocks.create!(name: text(row["name"]), segments: int(row["segments"]) || 6, public: row["public"] == true,
                                triggers: list(row["triggers"]), times: list(row["times"]), full_line: text(row["full_line"]),
                                impulse: text(row["impulse"]), portents: text(row["portents"]),
                                map_node: (node if node.is_a?(MapNode)), mode: (mode if mode.is_a?(Mode)))
      end
    end

    def secrets!(campaign)
      list(data["secrets"]).each do |row|
        node = @refs[row["place"]]
        npc = @refs[row["npc"]]
        campaign.secrets.create!(key: text(row["key"]), body: text(row["body"]), steps: text(row["steps"]),
                                 location: (node.location if node.is_a?(MapNode)), npc: (npc if npc.is_a?(Npc)))
      end
    end

    def scenes!(campaign)
      list(data["scenes"]).each do |row|
        node = @refs[row["place"]]
        mode = @refs[row["mode"]]
        scene = campaign.scenes.create!(name: text(row["name"]), ending: text(row["ending"]) || "none", encounter: hash(row["encounter"]),
                                        map_node: (node if node.is_a?(MapNode)), mode: (mode if mode.is_a?(Mode)))
        list(row["beats"]).each_with_index { |beat, i| beat!(scene, beat, i) }
      end
    end

    def beat!(scene, row, position)
      speaker = @refs[row["speaker"]]
      place = @refs[row["place"]]
      figures = list(row["figures"]).filter_map do |figure|
        npc = @refs[figure["npc"]]
        { "type" => "Npc", "id" => npc.id, "side" => figure["side"], "expression" => figure["expression"] } if npc.is_a?(Npc)
      end
      kind = text(row["kind"])
      beat = scene.beats.create!(kind: kind, position: position, speaker: (speaker if speaker.is_a?(Npc)), expression: text(row["expression"]),
                                 text: text(row["text"]).to_s, backdrop: text(row["backdrop"]) || "keep", map_node: (place if place.is_a?(MapNode)),
                                 figures: figures, cue: text(row["cue"]), options: list(row["options"]), flag_key: text(row["flag_key"]),
                                 action: text(row["action"]), fx: text(row["fx"]), transition: text(row["transition"]) || "fade",
                                 music: (kind == "music" ? beat_music(row["music"]) : nil))
      attach(beat.image, row["image"])
    end

    # A place's changes from what was rolled (Generators::Overrides), as far
    # as they make sense here: the shapes the generator reads, naming only
    # monsters and items the world has.
    def overrides(given)
      monsters = world.monsters.pluck(:slug).to_set
      items = world.items.pluck(:slug).to_set
      decision = lambda do |row|
        row = hash(row)
        kind = text(row["kind"])
        return unless Generators::Dungeon::DECISIONS.include?(kind)

        fight = hash(row["monsters"]).select { |slug, count| monsters.include?(slug) && int(count).to_i.positive? }.transform_values { |count| int(count).clamp(1, 8) }
        return if %w[encounter boss].include?(kind) && fight.empty?

        { "kind" => kind, "text" => text(row["text"]), "monsters" => fight.presence, "gil" => int(row["gil"]),
          "item" => (row["item"] if items.include?(row["item"])), "lock" => text(row["lock"]), "name" => text(row["name"]),
          "costly_path" => text(row["costly_path"]) }.compact
      end
      # A pinned room keeps its name and decision; a pinned service, its plain fields.
      pins = hash(given["pins"]).filter_map do |key, element|
        element = hash(element)
        if element.key?("decision")
          made = decision.(element["decision"]) or next
          [ key.to_s, { "name" => text(element["name"]), "decision" => made }.compact ]
        elsif element["key"] == key && element["kind"].is_a?(String) && element["name"].is_a?(String)
          [ key.to_s, element.select { |_, value| value.is_a?(String) || value.is_a?(Integer) || value == true || value == false } ]
        end
      end.to_h
      added = list(given["added_rooms"]).filter_map do |room|
        room = hash(room)
        made = decision.(room["decision"]) or next
        { "key" => text(room["key"]), "name" => text(room["name"]), "decision" => made, "connect" => text(room["connect"]) } if room["key"].is_a?(String) && room["connect"].is_a?(String)
      end
      boss = hash(given["boss"]).select { |slug, count| monsters.include?(slug) && int(count).to_i.positive? }.transform_values { |count| int(count).clamp(1, 8) }
      { "name" => text(given["name"]).presence, "pins" => pins.presence, "added_rooms" => added.presence, "boss" => boss.presence,
        "stock" => (list(given["stock"]).select { |slug| items.include?(slug) } if given.key?("stock")) }.compact
    end

    # --- small things -----------------------------------------------------------------

    def open_jobs
      slugs = list(data["open_jobs"]).map(&:to_s) & world.jobs.pluck(:slug)
      slugs.presence if data["open_jobs"].is_a?(Array)
    end

    def music(value)
      value = CampaignModule.portable_music(text(value))
      value if value && Campaign::MUSIC_CHOICES.include?(value)
    end

    def beat_music(value)
      value = CampaignModule.portable_music(text(value))
      value && world.music_choice?(value, extra: %w[follow]) ? value : "follow"
    end

    # A picture from the archive into its slot. A name the archive doesn't
    # have is skipped: the slot stays empty, as in a module without art.
    def attach(slot, name)
      asset = name.is_a?(String) && archive.assets[name]
      return unless asset && asset.content_type.start_with?("image/")

      slot.attach(io: StringIO.new(asset.bytes), filename: File.basename(asset.name), content_type: asset.content_type)
    end
  end
end
