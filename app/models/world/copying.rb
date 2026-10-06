# frozen_string_literal: true

# Starting a new world from another one's: its books, then its canon
# (atlas, cast, codex, fronts), each pointing at the new world's copies.
# Rules only takes the books and leaves the setting behind: no canon, and
# none of its voice, words, calendar, origins or history.
module World::Copying
  extend ActiveSupport::Concern

  BOOKS = %i[abilities items monsters encounter_tables generator_tables location_templates jobs].freeze
  COPIED = %w[id world_id created_at updated_at].freeze

  # Start a new world from another one's books: every entry is copied
  # (images too, sharing the stored file), so the author edits a working
  # setting instead of an empty one. Books refer to each other by slug, so
  # copies keep pointing at copies; the few id references are remapped.
  # Copied in dependency order, so each entry validates against the ones
  # it names. rules_only: the books without the setting (see above).
  def copy_books_from!(source, rules_only: false)
    transaction do
      # The setting's types and skills first: the books are checked against them.
      update!(damage_types: source.damage_types, terrain_types: source.terrain_types, skills: source.skills, battle_rules: source.battle_rules)
      tables = {}
      abilities = {}
      # Summons name creatures from the Bestiary, so they come after it.
      summoning = source.abilities.select { |a| Array(a.effects).any? { |e| e["primitive"] == "summon" } }.map(&:id)
      steps = BOOKS.flat_map do |book|
        entries = source.public_send(book)
        case book
        when :abilities then [ [ :abilities, entries.where.not(id: summoning) ] ]
        when :monsters then [ [ :monsters, entries ], [ :abilities, source.abilities.where(id: summoning) ] ]
        else [ [ book, entries ] ]
        end
      end
      steps.each do |book, entries|
        entries.find_each do |entry|
          copy = entry.dup
          copy.world = self
          copy.encounter_table_id = tables[entry.encounter_table_id] if book == :location_templates
          copy.save!
          copy.image.attach(entry.image.blob) if entry.image.attached?
          tables[entry.id] = copy.id if book == :encounter_tables
          abilities[entry.id] = copy.id if book == :abilities
          if book == :jobs
            entry.job_levels.each { |level| copy.job_levels.create!(level: level.level, ability_id: abilities.fetch(level.ability_id)) }
          end
        end
      end
      return if rules_only

      %w[voice avoid lines veils terms calendar origins history].each { |attr| self[attr] = source[attr] if self[attr].blank? }
      save!
      copy_canon_from!(source)
    end
  end

  # The atlas, cast and codex, pointing at this world's copies of the books.
  def copy_canon_from!(source)
    maps = {}
    source.world_maps.in_order.each do |sheet|
      maps[sheet.id] = world_maps.create!(sheet.attributes.except(*COPIED, "parent_id"))
      maps[sheet.id].image.attach(sheet.image.blob) if sheet.image.attached?
    end
    source.world_maps.where.not(parent_id: nil).find_each { |sheet| maps[sheet.id].update!(parent: maps[sheet.parent_id]) if maps[sheet.parent_id] }
    source.world_map_links.find_each { |link| world_map_links.create!(from_map: maps.fetch(link.from_map_id), to_map: maps.fetch(link.to_map_id), direction: link.direction) }
    places = {}
    source.world_places.find_each do |place|
      template = place.location_template && location_templates.find_by(slug: place.location_template.slug)
      places[place.id] = world_places.create!(place.attributes.except(*COPIED, "location_template_id", "world_map_id")
                                                   .merge(location_template: template, seed: place.seed, world_map: maps[place.world_map_id]))
    end
    source.world_routes.find_each do |route|
      table = route.encounter_table && encounter_tables.find_by(slug: route.encounter_table.slug)
      world_routes.create!(route.attributes.except(*COPIED, "from_place_id", "to_place_id", "encounter_table_id")
                                .merge(from_place: places.fetch(route.from_place_id), to_place: places.fetch(route.to_place_id), encounter_table: table))
    end
    source.world_figures.includes(portraits: { image_attachment: :blob }).find_each do |figure|
      copy = world_figures.create!(figure.attributes.except(*COPIED, "monster_id", "world_place_id")
                                         .merge(monster: figure.monster && monsters.find_by(slug: figure.monster.slug),
                                                world_place: places[figure.world_place_id]))
      figure.portraits.each { |p| copy.portraits.create!(expression: p.expression).image.attach(p.image.blob) if p.image.attached? }
    end
    source.codex_entries.find_each { |entry| codex_entries.create!(entry.attributes.except(*COPIED)) }
    # Fronts name places and people by id: point them at the copies.
    figures = source.world_figures.to_h { |f| [ f.id, world_figures.find_by(name: f.name)&.id ] }
    source.world_fronts.find_each do |front|
      world_fronts.create!(name: front.name, description: front.description, history_key: front.history_key,
                           clocks: front.clocks.map { |c|
                             c.attributes.slice("name", "segments", "triggers", "full_line", "public", "mode_name", "mode_line", "mode_description", "impulse", "portents")
                              .merge("place_id" => places[c.place_id]&.id)
                           },
                           secrets: front.secrets.map { |s|
                             { "body" => s.body, "place_id" => places[s.place_id]&.id, "figure_id" => figures[s.figure_id], "steps" => s.steps, "key" => s.key }
                           })
    end
  end
end
