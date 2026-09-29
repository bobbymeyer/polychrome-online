# frozen_string_literal: true

# The base world's first book entries (docs/HANDOFF.md §2: "The base world
# is seed data: the first World and its children").
#
# Worlds are live: a GM develops theirs as they play, editing entries in the
# books. So an ordinary run only adds what's missing (a new monster, a new
# table) and never touches an entry that's already there, edited or not.
# `bin/rails base_world:update` (overwrite: true) puts every entry back to
# what's written here, for when the seed data itself has been retuned.
# Numbers are first-pass tuning (§9.2).
module Seeds
  module BaseWorld
    module_function

    def run(overwrite: false)
      @overwrite = overwrite
      world = World.find_or_initialize_by(slug: "base")
      if world.new_record? || overwrite
        world.update!(name: "Base World",
                      description: "The opinionated default setting: crystals, jobs, and a world map of towns, " \
                                   "dungeons and the roads between them.",
                      damage_types: TypeChart.default_rows, terrain_types: TypeChart::DEFAULT_TERRAIN, skills: World::DEFAULT_SKILLS)
      end

      # Summons name their creatures, and creatures name what they do: the
      # rest first, then the creatures, then the summons.
      summons, others = ABILITIES.partition { |_, attrs| attrs[:effects].any? { |e| e[:primitive] == "summon" } }
      others.each { |slug, attrs| upsert(world.abilities, slug, attrs) }
      ITEMS.each { |slug, attrs| upsert(world.items, slug, attrs) }
      MONSTERS.each { |slug, attrs| upsert(world.monsters, slug, attrs) }
      summons.each { |slug, attrs| upsert(world.abilities, slug, attrs) }
      ENCOUNTER_TABLES.each { |slug, attrs| upsert(world.encounter_tables, slug, attrs) }
      GENERATOR_TABLES.each { |slug, attrs| upsert(world.generator_tables, slug, attrs) }
      LOCATION_TEMPLATES.each do |slug, attrs|
        table = attrs[:encounter_table] && world.encounter_tables.find_by!(slug: attrs[:encounter_table])
        upsert(world.location_templates, slug, attrs.except(:encounter_table).merge(encounter_table: table))
      end
      seed_atlas(world)
      JOBS.each do |slug, attrs|
        levels = attrs.fetch(:levels)
        fresh = !world.jobs.exists?(slug: slug.to_s)
        job = upsert(world.jobs, slug, attrs.except(:levels))
        next unless fresh || overwrite

        job.job_levels.destroy_all
        levels.each do |ability, level|
          job.job_levels.create!(level: level, ability: world.abilities.find_by!(slug: ability))
        end
      end
      world
    end

    # The setting's map (World#world_places, #world_routes): where a new
    # campaign starts (the first town) and the roads out of it, a safe one
    # and dangerous ones with their encounters. Places are known by name.
    def seed_atlas(world)
      places = PLACES.to_h do |name, attrs|
        template = attrs[:template] && world.location_templates.find_by!(slug: attrs[:template])
        place = world.world_places.find_or_initialize_by(name: name)
        place.update!(attrs.except(:template).merge(location_template: template)) if place.new_record? || @overwrite
        [ name, place ]
      end
      ROUTES.each do |from, to, attrs|
        a, b = places.fetch(from), places.fetch(to)
        next if world.world_routes.where(from_place: a, to_place: b).or(world.world_routes.where(from_place: b, to_place: a)).exists?

        table = attrs[:encounters] && world.encounter_tables.find_by!(slug: attrs[:encounters])
        world.world_routes.create!(from_place: a, to_place: b, encounter_table: table, **attrs.except(:encounters))
      end
      figures = FIGURES.to_h do |name, attrs|
        figure = world.world_figures.find_or_initialize_by(name: name)
        if figure.new_record? || @overwrite
          figure.update!(attrs.except(:monster, :place).merge(monster: world.monsters.find_by!(slug: attrs[:monster]), world_place: places.fetch(attrs[:place])))
        end
        [ name, figure ]
      end
      FRONTS.each do |name, attrs|
        front = world.world_fronts.find_or_initialize_by(name: name)
        next unless front.new_record? || @overwrite

        clocks = attrs[:clocks].map do |c|
          c.except(:place, :source).merge(place_id: places[c[:place]]&.id, source_id: places[c[:source]]&.id).transform_keys(&:to_s)
        end
        secrets = attrs[:secrets].map { |x| { "body" => x[:body], "place_id" => places[x[:place]]&.id, "figure_id" => figures[x[:figure]]&.id } }
        front.update!(description: attrs[:description], clocks: clocks, secrets: secrets)
      end
    end

    # Create the entry if it's missing; only rewrite an existing one when
    # overwriting.
    def upsert(scope, slug, attrs)
      record = scope.find_or_initialize_by(slug: slug.to_s)
      record.update!(attrs) if record.new_record? || @overwrite
      record
    end

    def stats(max_hp:, max_mp: 0, str: 10, mag: 10, vit: 10, spr: 10, agi: 10, atk: 0, def: 0, mdef: 0)
      { max_hp:, max_mp:, str:, mag:, vit:, spr:, agi:, atk:, def:, mdef: }
    end

    def texts(*strings, **fields)
      strings.map { |text| { text: text }.merge(fields) }
    end
  end
end

# The books, by file: each defines its constants inside Seeds::BaseWorld.
require_relative "base_world/abilities"
require_relative "base_world/items"
require_relative "base_world/jobs"
require_relative "base_world/monsters"
require_relative "base_world/tables"
require_relative "base_world/atlas"
require_relative "base_world/templates"
