# frozen_string_literal: true

# The book entries a module carries (CampaignModule): everything its prep
# names, and everything those name in turn. A monster brings its moves,
# its forms and its drops; a move brings the creature it summons and the
# mask it puts on; a mask brings its moves; a template brings its
# encounters and tables; an encounter table brings its monsters; a stock
# or treasure table brings its items.
module CampaignModule
  class Books
    # In the order the world's books list them; an import saves them in as
    # many passes as their references need (PackageBooks.add!).
    KINDS = {
      "abilities" => :abilities, "items" => :items, "monsters" => :monsters,
      "encounter_tables" => :encounter_tables, "generator_tables" => :generator_tables, "location_templates" => :location_templates
    }.freeze
    attr_reader :world, :wanted

    def initialize(world)
      @world = world
      @wanted = KINDS.keys.index_with { Set.new }
    end

    def monster!(slug) = want("monsters", slug)
    def item!(slug) = want("items", slug)
    def ability!(slug) = want("abilities", slug)
    def encounter_table!(slug) = want("encounter_tables", slug)
    def location_template!(slug) = want("location_templates", slug)

    # A room's decision, a scene's fight, a stock list: { slug => count } or an item.
    def decision!(decision)
      return unless decision.is_a?(Hash)

      decision.fetch("monsters", {}).to_h.each_key { |slug| monster!(slug) }
      Array(decision["waves"]).each { |wave| wave.to_h.each_key { |slug| monster!(slug) } if wave.is_a?(Hash) }
      crew!(decision["crew"]) if decision["crew"].is_a?(Hash)
      item!(decision["item"]) if decision["item"].present?
    end

    # A crewed fight's stations are Bestiary entries too (Crew).
    def crew!(crew)
      stations = crew["stations"].to_h.values + [ crew["default"] ] + Array(crew["wearers"]).map { |row| row.is_a?(Hash) ? row["station"] : nil }
      stations.compact.uniq.each { |slug| monster!(slug) if slug.is_a?(String) }
    end

    # Every entry wanted, its references followed: { kind => [entry, ...] }.
    def entries
      @entries ||= begin
        found = KINDS.keys.index_with { {} }
        queue = wanted.flat_map { |kind, slugs| slugs.map { |slug| [ kind, slug ] } }
        until queue.empty?
          kind, slug = queue.shift
          next if slug.blank? || found[kind].key?(slug)

          entry = world.public_send(KINDS.fetch(kind)).find_by(slug: slug) or next
          found[kind][slug] = entry
          queue.concat(references(kind, entry))
        end
        found.transform_values(&:values)
      end
    end

    private

    def want(kind, slug)
      wanted.fetch(kind) << slug.to_s if slug.present?
    end

    def references(kind, entry)
      case kind
      when "monsters"
        entry.ability_slugs.map { |slug| [ "abilities", slug ] } +
          entry.phases.map { |phase| [ "monsters", phase["becomes"] ] } +
          entry.drops.map { |drop| [ "items", drop["item"] ] }
      when "abilities", "items"
        effects = Array(entry.effects)
        refs = effects.filter_map { |e| [ "monsters", e["creature"] ] if e["creature"].present? } +
               effects.filter_map { |e| [ "items", e["mask"] ] if e["mask"].present? }
        refs += Array(entry.mask["abilities"]).map { |slug| [ "abilities", slug ] } if kind == "items" && entry.mask.present?
        refs
      when "encounter_tables"
        entry.entries.flat_map { |row| row.fetch("monsters", {}).keys.map { |slug| [ "monsters", slug ] } }
      when "generator_tables"
        entry.entries.filter_map { |row| [ "items", row["item"] ] if row["item"].present? }
      when "location_templates"
        [ ([ "encounter_tables", entry.encounter_table.slug ] if entry.encounter_table) ].compact +
          entry.config.fetch("boss", {}).keys.map { |slug| [ "monsters", slug ] } +
          entry.generator_tables.map { |table| [ "generator_tables", table.slug ] }
      else []
      end
    end
  end
end
