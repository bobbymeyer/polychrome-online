# frozen_string_literal: true

# What's in a place is never stored: it's rolled from the template and seed
# every time (Generators::Town / ::Dungeon), given its past
# (Generators::Provenance), and the GM's overrides laid on top
# (Generators::Overrides). A reroll is just a new seed.
module Location::Generation
  extend ActiveSupport::Concern

  # Rolled, then given its past (Generators::Provenance): a dungeon's rooms,
  # boss and treasure follow from what it was.
  def generated
    @generated ||= begin
      rolled = if town?
        in_the_worlds_words(Generators::Town.generate(seed: seed, template: town_settings, tables: tables))
      else
        Generators::Dungeon.generate(seed: seed, template: location_template.settings,
                                     encounters: location_template.encounter_table&.entries || [],
                                     tables: tables)
      end
      rolled = Generators::Provenance.apply(rolled, past_for(rolled["name"]), seed: seed, lore: campaign.world.lore)
      elaborated(rolled)
    end
  end

  # The GM's elaboration scale (Generators::Elaboration): extra rooms and
  # passages around the core, which it cannot reshape.
  #
  # AFTER Provenance, and that ordering is load-bearing. Provenance renames
  # the rooms that aren't the entrance or the boss from the past's names,
  # picks one event room to carry the fall's trace, and deals heirlooms out
  # to the treasure rooms -- all by walking rooms. Elaborating first would
  # change which core room got which, so the dial would alter the core. This
  # way the core is finished before a thing is added to it.
  def elaborated(rolled)
    return rolled unless rolled["kind"] == "dungeon" && elaboration.positive?

    # variant: this location's own name, so two dungeons that a seeder gave
    # the same seed don't elaborate into the same rooms. Its name rather than
    # its id: stable if the campaign is seeded again, and unique on an island.
    Generators::Elaboration.apply(rolled, level: elaboration, seed: seed, variant: name,
                                  encounters: location_template.encounter_table&.entries || [],
                                  tables: tables)
  end

  def view
    @view ||= with_stock_stories(Generators::Overrides.apply(generated, overrides))
  end

  # Its past: the atlas place's, written by the world's history (Chronicle)
  # or the GM; else a small one of its own, rolled from its seed.
  def past_for(name)
    written = map_node&.world_place&.past
    return written.except("edited") if Past.new(written).present?

    world = campaign.world
    Generators::Provenance.past_for(seed: seed, name: name, kind: kind,
                                    given_names: tables.fetch("names", []).filter_map { |e| e["text"] }.presence || world.given_names,
                                    family_names: overrides["families"] || world.family_names, lore: world.lore)
  end

  def past = Past.new(generated["past"], lore: campaign.world.lore)

  # The tables it's rolled from: the world's, as they are. Once the party
  # has been here, the ones it was rolled from then (#remember!), so the
  # people they met keep their names when the world's tables change.
  def tables
    overrides["tables"] || location_template.table_entries
  end

  # The party got here: from now on it's rolled from the tables as they are
  # now. A reroll (Location#reroll!) takes the world's again.
  def remember!
    return if overrides.key?("tables")

    update!(overrides: overrides.merge("tables" => location_template.table_entries, "families" => campaign.world.family_names))
  end

  # Who made the shop's made things (not its potions), and who had them.
  def with_stock_stories(view)
    return view unless view["kind"] == "town" && view["stock"].present?

    made = campaign.world.items.where(slug: view["stock"]).where.not(category: "consumable").pluck(:slug)
    view.merge("stock_stories" => Generators::Provenance.stock(made.sort, view["past"], seed: seed, lore: campaign.world.lore))
  end

  # The template's settings, less the services this world doesn't have.
  def town_settings
    settings = location_template.settings
    off = campaign.world.services_off
    return settings if off.empty?

    settings.merge("services" => settings.fetch("services", {}).merge(off.index_with(0)))
  end

  # Where the world has its own word for a service, its keeper goes by the
  # place they keep ("Keeper of The Quiet Shelf"): "Menders keeper" reads
  # badly, and the game's own "Priest" would be the wrong word.
  def in_the_worlds_words(town)
    world = campaign.world
    names = town.fetch("services", []).to_h { |s| [ s["kind"], s["name"] ] }
    town.merge("npcs" => town["npcs"].map do |npc|
      kind = npc["service"]
      kind && world.terms.dig("services", kind) ? npc.merge("title" => "Keeper of #{names[kind] || world.word("service.#{kind}")}") : npc
    end)
  end

  def reload(*)
    @generated = @view = nil
    super
  end
end
