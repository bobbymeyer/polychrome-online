# frozen_string_literal: true

# A campaign's prep, written out as a module (CampaignModule). Records
# point at each other by refs ("place-12", "npc-3"), never by this
# database's ids; book entries by slug; pictures by their name in the
# archive.
module CampaignModule
  class Export
    attr_reader :campaign

    def initialize(campaign)
      @campaign = campaign
      @books = Books.new(campaign.world)
      @assets = {}
    end

    def to_zip = PackageArchive.new(FORMAT, data, @assets).to_zip

    def filename = "#{campaign.name.parameterize.presence || 'campaign'}.module.zip"

    def data
      @data ||= begin
        body = {
          "format" => FORMAT, "version" => VERSION, "name" => campaign.name, "exported_at" => Time.current.iso8601,
          "world" => { "slug" => campaign.world.slug, "name" => campaign.world.name },
          "lines" => campaign.lines, "veils" => campaign.veils, "open_jobs" => campaign.open_jobs,
          "start" => ref(campaign.current_node),
          "maps" => maps, "map_links" => map_links, "places" => places, "roads" => roads, "cast" => cast,
          "clocks" => clocks, "secrets" => secrets, "scenes" => scenes, "flags" => flags, "rumours" => rumours
        }
        body.merge("books" => books)
      end
    end

    private

    def ref(record) = record && "#{record.class.name.underscore.dasherize}-#{record.id}"

    # A picture into the archive, once however often it's used: its name there, or nil.
    def asset(attachment)
      return unless attachment&.attached?

      blob = attachment.blob
      ext = File.extname(blob.filename.to_s).delete(".").downcase.presence || Rack::Mime::MIME_TYPES.invert[blob.content_type]&.delete(".") || "png"
      name = "assets/#{blob.checksum.to_s.unpack1('m0').unpack1('H*')}.#{ext}"
      return unless PackageArchive.asset_name?(FORMAT, name)

      @assets[name] ||= blob.download
      name
    end

    def maps
      campaign.maps.in_order.map do |map|
        { "ref" => ref(map), "name" => map.name, "parent" => ref(map.parent), "x" => map.x, "y" => map.y,
          "description" => map.description, "image" => asset(map.image) }
      end
    end

    def map_links
      campaign.map_links.map { |link| { "from" => ref(link.from_map), "to" => ref(link.to_map), "direction" => link.direction } }
    end

    def places
      campaign.map_nodes.includes(:map, :modes, location: :location_template).order(:id).map do |node|
        { "ref" => ref(node), "name" => node.name, "kind" => node.kind, "x" => node.x, "y" => node.y, "visible" => node.visible,
          "map" => ref(node.map), "description" => node.description, "notes" => node.notes, "activities" => node.activities,
          "location" => location(node.location), "modes" => node.modes.map { |mode| mode_data(mode, node.location) } }
      end
    end

    def location(location)
      return unless location

      @books.location_template!(location.location_template.slug)
      overrides = location.overrides.except("tables", "families")
      overrides.fetch("pins", {}).each_value { |room| @books.decision!(room["decision"]) }
      overrides.fetch("added_rooms", []).each { |room| @books.decision!(room["decision"]) }
      overrides.fetch("boss", {}).each_key { |slug| @books.monster!(slug) }
      Array(overrides["stock"]).each { |slug| @books.item!(slug) }
      { "ref" => ref(location), "template" => location.location_template.slug, "seed" => location.seed, "overrides" => overrides }
    end

    def mode_data(mode, location)
      @books.encounter_table!(mode.encounter_table.slug) if mode.encounter_table
      art = location && mode.mode_art&.location_id == location.id ? mode.mode_art : nil
      { "ref" => ref(mode), "key" => mode.key, "name" => mode.name, "line" => mode.line, "description" => mode.description,
        "closed" => mode.closed, "music" => CampaignModule.portable_music(mode.music), "times" => mode.times, "activities" => mode.activities,
        "encounters" => mode.encounter_table&.slug, "picture" => asset(art&.image) }
    end

    def roads
      campaign.map_edges.includes(:encounter_table).order(:id).map do |edge|
        @books.encounter_table!(edge.encounter_table.slug) if edge.encounter_table
        { "from" => ref(edge.from_node), "to" => ref(edge.to_node), "state" => edge.state, "duration" => edge.duration,
          "travel_event" => edge.travel_event, "encounters" => edge.encounter_table&.slug, "waypoints" => edge.waypoints }
      end
    end

    def cast
      campaign.npcs.includes(:monster, :sprite, location: :map_node, portraits: { image_attachment: :blob }).order(:id).map do |npc|
        @books.monster!(npc.monster.slug) if npc.monster
        { "ref" => ref(npc), "name" => npc.name, "title" => npc.title, "description" => npc.description, "colour" => npc.colour,
          "monster" => npc.monster&.slug, "home" => ref(npc.location&.map_node), "location_key" => npc.location_key,
          "portraits" => npc.portraits.to_h { |portrait| [ portrait.expression, asset(portrait.image) ] }.compact,
          "sprite" => asset(npc.sprite&.image) }
      end
    end

    def clocks
      campaign.clocks.order(:id).map do |clock|
        { "name" => clock.name, "segments" => clock.segments, "public" => clock.public, "triggers" => clock.triggers, "times" => clock.times,
          "full_line" => clock.full_line, "impulse" => clock.impulse, "portents" => clock.portents,
          "place" => ref(clock.map_node), "mode" => ref(clock.mode) }
      end
    end

    def secrets
      campaign.secrets.includes(location: :map_node).order(:id).map do |secret|
        { "key" => secret.key, "body" => secret.body, "steps" => secret.steps, "place" => ref(secret.location&.map_node), "npc" => ref(secret.npc) }
      end
    end

    def scenes
      campaign.scenes.includes(beats: { image_attachment: :blob }).order(:created_at, :id).map do |scene|
        scene.encounter.each_key { |slug| @books.monster!(slug) }
        { "name" => scene.name, "ending" => scene.ending, "encounter" => scene.encounter, "place" => ref(scene.map_node), "mode" => ref(scene.mode),
          "beats" => scene.beats.map { |beat| beat_data(beat) } }
      end
    end

    # A line said by one of the party has nobody to say it in a module: the narrator does.
    def beat_data(beat)
      npc = beat.speaker if beat.speaker_type == "Npc"
      figures = beat.figures.filter_map do |figure|
        { "npc" => "npc-#{figure['id']}", "side" => figure["side"], "expression" => figure["expression"] } if figure["type"] == "Npc"
      end
      { "kind" => beat.kind, "speaker" => ref(npc), "expression" => beat.expression, "text" => beat.text, "backdrop" => beat.backdrop,
        "place" => ref(beat.map_node), "figures" => figures, "cue" => beat.cue, "music" => CampaignModule.portable_music(beat.music),
        "options" => beat.options, "flag_key" => beat.flag_key, "action" => beat.action, "fx" => beat.fx, "transition" => beat.transition,
        "image" => asset(beat.image) }
    end

    def flags
      campaign.flags.order(:key).map { |flag| { "key" => flag.key, "value" => flag.value, "note" => flag.note } }
    end

    # Talk going round that the party hasn't heard yet, where it started.
    def rumours
      campaign.rumours.where(heard: false, faded: false, deed: nil).order(:id).map do |rumour|
        { "body" => rumour.body, "at" => ref(rumour.origin), "about" => ref(rumour.about), "sway" => rumour.sway }
      end
    end

    def books
      @books.entries.to_h do |kind, entries|
        [ kind, entries.sort_by(&:slug).map { |entry| PackageBooks.attributes(entry).merge("image" => asset(entry.image)) } ]
      end
    end
  end
end
