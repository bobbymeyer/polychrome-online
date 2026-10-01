# frozen_string_literal: true

# Writes a setting from constants: its world row, its books, and its canon
# (atlas, cast, fronts, codex). The seeded worlds (Seeds::BaseWorld,
# Seeds::Greenware) describe themselves as constants and hand them here.
#
# Worlds are live: a GM develops theirs as they play, editing entries in the
# books. So an ordinary run only adds what's missing (a new monster, a new
# table) and never touches an entry that's already there, edited or not.
# Overwriting (bin/rails base_world:update, worlds:update[slug]) puts every
# entry back to what's written in the seed, for when the seed itself has
# been retuned.
module Seeds
  # Helpers the seed constants are written with.
  module Helpers
    def stats(max_hp:, max_mp: 0, str: 10, mag: 10, vit: 10, spr: 10, agi: 10, atk: 0, def: 0, mdef: 0)
      { max_hp:, max_mp:, str:, mag:, vit:, spr:, agi:, atk:, def:, mdef: }
    end

    def texts(*strings, **fields)
      strings.map { |text| { text: text }.merge(fields) }
    end
  end

  class Setting
    # Everything a setting can be seeded with. Books refer to each other by
    # slug; the canon names places, figures and tables by name or slug.
    def initialize(slug:, world:, abilities: {}, items: {}, monsters: {}, encounter_tables: {}, generator_tables: {},
                   location_templates: {}, jobs: {}, payoffs: {}, places: {}, routes: [], figures: {}, fronts: {}, codex: {}, history: nil)
      @slug = slug.to_s
      @world_attrs = world
      @abilities, @items, @monsters, @encounter_tables = abilities, items, monsters, encounter_tables
      @generator_tables, @location_templates, @jobs, @payoffs = generator_tables, location_templates, jobs, payoffs
      @places, @routes, @figures, @fronts, @codex, @history = places, routes, figures, fronts, codex, history
    end

    def run(overwrite: false)
      @overwrite = overwrite
      world = World.find_or_initialize_by(slug: @slug)
      world.update!(@world_attrs) if world.new_record? || overwrite
      seed_books(world)
      seed_atlas(world)
      seed_codex(world)
      seed_history(world)
      world
    end

    private

    def seed_books(world)
      # Summons name their creatures, and creatures name what they do: the
      # rest first, then the creatures, then the summons.
      summons, others = @abilities.partition { |_, attrs| attrs[:effects].any? { |e| e[:primitive] == "summon" } }
      others.each { |slug, attrs| upsert(world.abilities, slug, attrs) }
      @items.each { |slug, attrs| upsert(world.items, slug, attrs) }
      @monsters.each { |slug, attrs| upsert(world.monsters, slug, attrs) }
      summons.each { |slug, attrs| upsert(world.abilities, slug, attrs) }
      @encounter_tables.each { |slug, attrs| upsert(world.encounter_tables, slug, attrs) }
      @generator_tables.each { |slug, attrs| upsert(world.generator_tables, slug, attrs) }
      @location_templates.each do |slug, attrs|
        table = attrs[:encounter_table] && world.encounter_tables.find_by!(slug: attrs[:encounter_table])
        upsert(world.location_templates, slug, attrs.except(:encounter_table).merge(encounter_table: table))
      end
      @jobs.each do |slug, attrs|
        levels = attrs.fetch(:levels)
        fresh = !world.jobs.exists?(slug: slug.to_s)
        job = upsert(world.jobs, slug, attrs.except(:levels).merge(payoff: @payoffs.fetch(slug.to_s, {})))
        next unless fresh || @overwrite

        job.job_levels.destroy_all
        levels.each do |ability, level|
          job.job_levels.create!(level: level, ability: world.abilities.find_by!(slug: ability))
        end
      end
    end

    # The setting's map (World#world_places, #world_routes): where a new
    # campaign starts (the first town) and the roads out of it, a safe one
    # and dangerous ones with their encounters. Places are known by name.
    def seed_atlas(world)
      places = @places.to_h do |name, attrs|
        template = attrs[:template] && world.location_templates.find_by!(slug: attrs[:template])
        place = world.world_places.find_or_initialize_by(name: name)
        place.update!(attrs.except(:template).merge(location_template: template)) if place.new_record? || @overwrite
        [ name, place ]
      end
      @routes.each do |from, to, attrs|
        a, b = places.fetch(from), places.fetch(to)
        next if world.world_routes.where(from_place: a, to_place: b).or(world.world_routes.where(from_place: b, to_place: a)).exists?

        table = attrs[:encounters] && world.encounter_tables.find_by!(slug: attrs[:encounters])
        world.world_routes.create!(from_place: a, to_place: b, encounter_table: table, **attrs.except(:encounters))
      end
      figures = @figures.to_h do |name, attrs|
        figure = world.world_figures.find_or_initialize_by(name: name)
        if figure.new_record? || @overwrite
          monster = attrs[:monster] && world.monsters.find_by!(slug: attrs[:monster])
          figure.update!(attrs.except(:monster, :place).merge(monster: monster, world_place: attrs[:place] && places.fetch(attrs[:place])))
        end
        [ name, figure ]
      end
      @fronts.each do |name, attrs|
        front = world.world_fronts.find_or_initialize_by(name: name)
        next unless front.new_record? || @overwrite

        clocks = attrs.fetch(:clocks, []).map do |c|
          c.except(:place, :source).merge(place_id: places[c[:place]]&.id, source_id: places[c[:source]]&.id).transform_keys(&:to_s)
        end
        secrets = attrs.fetch(:secrets, []).map do |x|
          { "body" => x[:body], "place_id" => places[x[:place]]&.id, "figure_id" => figures[x[:figure]]&.id, "steps" => x[:steps], "key" => x[:key] }
        end
        front.update!(description: attrs[:description], clocks: clocks, secrets: secrets)
      end
    end

    # The world's lore pages: a players' side, and the GM's notes.
    def seed_codex(world)
      @codex.each do |title, attrs|
        entry = world.codex_entries.find_or_initialize_by(title: title)
        entry.update!(attrs) if entry.new_record? || @overwrite
      end
    end

    # The settings of the world's pocket history (Chronicle): its seed, its
    # span and the families kept through rerolls, each seated at a place by
    # name. With write: true it's rolled and written into the canon too
    # (the same seed, the same history); otherwise that's done from the
    # world's history page. A place whose past the seed wrote is left be.
    def seed_history(world)
      return unless @history
      return unless world.history.blank? || @overwrite

      families = Array(@history[:families]).map do |f|
        seat = f[:seat] && world.world_places.find_by!(name: f[:seat])
        { "name" => f[:name], "trade" => f[:trade], "seat" => seat && "place-#{seat.id}" }.compact
      end
      world.update!(history: { "seed" => @history[:seed], "years" => @history[:years], "families" => families }.compact)
      Chronicle.new(world).write! if @history[:write]
    end

    # Create the entry if it's missing; only rewrite an existing one when
    # overwriting.
    def upsert(scope, slug, attrs)
      record = scope.find_or_initialize_by(slug: slug.to_s)
      record.update!(attrs) if record.new_record? || @overwrite
      record
    end
  end
end
