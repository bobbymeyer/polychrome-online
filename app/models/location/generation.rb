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
        in_the_worlds_words(Generators::Town.generate(seed: seed, template: town_settings, tables: location_template.table_entries))
      else
        Generators::Dungeon.generate(seed: seed, template: location_template.settings,
                                     encounters: location_template.encounter_table&.entries || [],
                                     tables: location_template.table_entries)
      end
      Generators::Provenance.apply(rolled, past_for(rolled["name"]), seed: seed)
    end
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
                                    given_names: location_template.table_entries.fetch("names", []).filter_map { |e| e["text"] },
                                    family_names: world.family_names)
  end

  def past = Past.new(generated["past"])

  # Who made the shop's made things (not its potions), and who had them.
  def with_stock_stories(view)
    return view unless view["kind"] == "town" && view["stock"].present?

    made = campaign.world.items.where(slug: view["stock"]).where.not(category: "consumable").pluck(:slug)
    view.merge("stock_stories" => Generators::Provenance.stock(made.sort, view["past"], seed: seed))
  end

  # The template's settings, less the services this world doesn't have.
  def town_settings
    settings = location_template.settings
    off = campaign.world.services_off
    return settings if off.empty?

    settings.merge("services" => settings.fetch("services", {}).merge(off.index_with(0)))
  end

  # A keeper is named for the world's word for their service.
  def in_the_worlds_words(town)
    world = campaign.world
    town.merge("npcs" => town["npcs"].map do |npc|
      kind = npc["service"]
      kind && world.terms.dig("services", kind) ? npc.merge("title" => "#{world.word("service.#{kind}")} keeper") : npc
    end)
  end

  def reload(*)
    @generated = @view = nil
    super
  end
end
