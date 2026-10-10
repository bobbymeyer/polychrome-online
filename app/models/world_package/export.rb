# frozen_string_literal: true

# A world written out as a package (WorldPackage). Book entries name each
# other by slug; canon points at canon by refs ("place-12", "figure-3");
# pictures and music by their name in the archive.
module WorldPackage
  class Export
    attr_reader :world

    def initialize(world)
      @world = world
      @assets = {}
    end

    def to_zip = PackageArchive.new(FORMAT, data, @assets).to_zip

    def filename = "#{world.slug.dasherize}.world.zip"

    def data
      @data ||= {
        "format" => FORMAT, "version" => VERSION, "name" => world.name, "slug" => world.slug, "exported_at" => Time.current.iso8601,
        "world" => world.attributes.slice(*SETTING),
        "books" => books, "tracks" => tracks,
        "maps" => maps, "map_links" => map_links, "places" => places, "routes" => routes, "figures" => figures,
        "codex" => codex, "fronts" => fronts
      }
    end

    private

    def ref(record) = record && "#{record.class.name.underscore.dasherize}-#{record.id}"

    # A file into the archive, once however often it's used: its name there, or nil.
    def asset(attachment)
      return unless attachment&.attached?

      blob = attachment.blob
      ext = File.extname(blob.filename.to_s).delete(".").downcase
      name = "assets/#{blob.checksum.to_s.unpack1('m0').unpack1('H*')}.#{ext}"
      return unless PackageArchive.asset_name?(FORMAT, name)

      @assets[name] ||= blob.download
      name
    end

    def books
      PackageBooks::KINDS.to_h do |kind, scope|
        entries = world.public_send(scope).with_attached_image.order(:slug)
        [ kind, entries.map { |entry| PackageBooks.attributes(entry).merge("image" => asset(entry.image)) } ]
      end
    end

    def tracks
      world.tracks.map do |track|
        { "ref" => ref(track), "name" => track.name, "scene" => track.scene, "source" => track.source, "url" => track.url,
          "position" => track.position, "audio" => asset(track.audio) }
      end
    end

    def maps
      world.world_maps.in_order.map do |map|
        { "ref" => ref(map), "name" => map.name, "parent" => ref(map.parent), "x" => map.x, "y" => map.y,
          "description" => map.description, "image" => asset(map.image) }
      end
    end

    def map_links
      world.world_map_links.map { |link| { "from" => ref(link.from_map), "to" => ref(link.to_map), "direction" => link.direction } }
    end

    def places
      world.world_places.includes(:location_template, :world_map).order(:id).map do |place|
        place.attributes.slice(*%w[name kind x y known description notes seed past lead activities night_line])
             .merge("ref" => ref(place), "template" => place.location_template&.slug, "map" => ref(place.world_map))
      end
    end

    def routes
      world.world_routes.includes(:encounter_table).order(:id).map do |route|
        route.attributes.slice(*%w[state travel_event duration waypoints])
             .merge("from" => ref(route.from_place), "to" => ref(route.to_place), "encounters" => route.encounter_table&.slug)
      end
    end

    def figures
      world.world_figures.includes(:monster, :world_place, :sprite, portraits: { image_attachment: :blob }).order(:id).map do |figure|
        figure.attributes.slice(*%w[name title blurb description colour history_key edited])
              .merge("ref" => ref(figure), "monster" => figure.monster&.slug, "place" => ref(figure.world_place),
                     "portraits" => figure.portraits.to_h { |portrait| [ portrait.expression, asset(portrait.image) ] }.compact,
                     "sprite" => asset(figure.sprite&.image))
      end
    end

    def codex
      world.codex_entries.order(:id).map { |entry| entry.attributes.slice(*%w[title category body gm_notes public history_key edited]) }
    end

    def fronts
      world.world_fronts.includes(:clocks, :secrets).order(:id).map do |front|
        { "name" => front.name, "description" => front.description, "history_key" => front.history_key, "edited" => front.edited,
          "clocks" => front.clocks.map { |clock|
            clock.attributes.slice(*%w[name segments triggers full_line public mode_name mode_line mode_description impulse portents])
                 .merge("place" => ref(clock.place), "source" => ref(clock.source))
          },
          "secrets" => front.secrets.map { |secret|
            secret.attributes.slice(*%w[body steps key]).merge("place" => ref(secret.place), "figure" => ref(secret.figure))
          } }
      end
    end
  end
end
