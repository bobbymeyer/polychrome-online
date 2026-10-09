# frozen_string_literal: true

# Masks belong to one campaign, Dead Calm: seven of them, and that's all
# (docs/ODA.md, Masks). Oda was first seeded with six of its own, their moves,
# and a mask-maker (Mother Quill and her workshop); the seed no longer
# writes them, and this takes them out of a database that has them. Only
# what nothing uses goes: a mask in someone's bag or worn stays, for its
# GM to deal with. A campaign that brought in the mask-maker keeps its own
# copies of her and her workshop (they're the campaign's), unlinked.
class RemoveOdasOwnMasks < ActiveRecord::Migration[8.1]
  MASKS = %w[storm_mask ember_fox_mask tide_mask stone_mask gale_mask hollow_mask].freeze
  MOVES = %w[raijin_strike foxfire riptide mountain_breaker cyclone_edge swallow_the_light].freeze

  def up
    world = World.find_by(slug: "oda") or return

    world.items.where(slug: MASKS).find_each do |mask|
      next if Inventory.exists?(item_id: mask.id) || EquipmentSlot.exists?(item_id: mask.id)

      mask.destroy!
    end
    world.abilities.where(slug: MOVES).find_each do |move|
      next if world.items.where(category: "mask").any? { |mask| Array(mask.mask["abilities"]).include?(move.slug) }

      move.destroy || say("Kept #{move.name}: #{move.errors.full_messages.to_sentence}")
    end
    FrontSecret.joins(:world_front).where(world_fronts: { world_id: world.id }).where("body LIKE ?", "The Hollow Mask%").destroy_all
    world.world_figures.find_by(name: "Mother Quill")&.destroy!
    world.world_places.find_by(name: "The Mask-Maker's Workshop")&.destroy!
    world.codex_entries.find_by(title: "Masks")&.destroy!
  end

  def down
    # The seed wrote them; bin/rails worlds:update[oda] writes what the seed says now, which is none of them.
  end
end
