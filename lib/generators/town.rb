# frozen_string_literal: true

module Generators
  # The town generator (docs/HANDOFF.md §7): a service roster, an NPC roster
  # with one-line hooks, shop stock, and a skyline built from building
  # archetypes. Pure: plain data in, plain data out, same seed, same town.
  #
  # template: { "services" => { "inn" => 100, "shop" => 80, ... },   percent chance each
  #             "npcs" => [min, max], "stock" => [min, max], "buildings" => [min, max] }
  # tables:   { "place_names" | "names" | "hooks" | "service_names" | "buildings" | "stock" => [entries] }
  #
  # Every generated element has a stable "key", which GM pins refer to.
  module Town
    SERVICES = %w[inn shop guild temple].freeze
    ROOFS = %w[peak flat dome].freeze

    module_function

    def generate(seed:, template:, tables:)
      pool = Pool.new(Battle::Rng.new(seed))
      services = services(pool, template, tables)
      {
        "kind" => "town",
        "name" => pool.pick(tables.fetch("place_names", []))&.fetch("text") || "Nameless Town",
        "services" => services,
        "npcs" => npcs(pool, template, tables, services),
        "stock" => stock(pool, template, tables, services),
        "skyline" => skyline(pool, template, tables, services)
      }
    end

    def services(pool, template, tables)
      chances = template.fetch("services", {})
      SERVICES.filter_map do |kind|
        next unless pool.percent?(chances.fetch(kind, 0).to_i)

        names = tables.fetch("service_names", []).select { |e| e["service"] == kind }
        { "key" => "service-#{kind}", "kind" => kind, "name" => pool.pick(names)&.fetch("text") || kind.capitalize }
      end
    end

    # Each service gets a keeper; the rest of the roster are townsfolk.
    def npcs(pool, template, tables, services)
      min, max = template.fetch("npcs", [ 3, 5 ])
      count = [ pool.between(min, max), services.size ].max
      names = pool.sample(tables.fetch("names", []), count)
      hooks = pool.sample(tables.fetch("hooks", []), count)
      Array.new(count) do |i|
        service = services[i]
        {
          "key" => "npc-#{i}",
          "name" => names[i]&.fetch("text") || "Stranger #{i + 1}",
          "title" => service ? KEEPERS.fetch(service["kind"]) : "Townsfolk",
          "service" => service&.fetch("kind"),
          "hook" => hooks[i]&.fetch("text")
        }.compact
      end
    end

    KEEPERS = { "inn" => "Innkeeper", "shop" => "Shopkeeper", "guild" => "Guildmaster", "temple" => "Priest" }.freeze

    def stock(pool, template, tables, services)
      return [] unless services.any? { |s| s["kind"] == "shop" }

      min, max = template.fetch("stock", [ 4, 6 ])
      pool.sample(tables.fetch("stock", []).select { |e| e["item"] }, pool.between(min, max))
          .map { |entry| entry["item"] }
    end

    # Buildings left to right. Service buildings come from archetypes tagged
    # with that service and are always included; the rest fill the row.
    def skyline(pool, template, tables, services)
      archetypes = tables.fetch("buildings", [])
      min, max = template.fetch("buildings", [ 8, 12 ])
      plain = archetypes.reject { |a| a["service"] }
      row = services.map do |service|
        archetype = pool.pick(archetypes.select { |a| a["service"] == service["kind"] })
        building(pool, archetype, service["kind"])
      end
      (pool.between(min, max) - row.size).times { row << building(pool, pool.pick(plain), nil) }
      order = row.sort_by { pool.int(1000) }
      order.each_with_index.map { |b, i| b.merge("key" => "building-#{i}") }
    end

    def building(pool, archetype, service)
      archetype ||= {}
      {
        "label" => archetype["text"],
        "service" => service,
        "width" => (archetype["width"] || 60).to_i + pool.int(21) - 10,
        "height" => (archetype["height"] || 70).to_i + pool.int(31) - 15,
        "roof" => ROOFS.include?(archetype["roof"]) ? archetype["roof"] : ROOFS[pool.int(ROOFS.size)]
      }.compact
    end
  end
end
