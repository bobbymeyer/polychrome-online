# frozen_string_literal: true

# Holding items: a character's own bag, and the party's chest (Campaign).
# Each is rows of Inventory (Carrying#carried); what they do with them is
# the same. Includers say which rows are theirs (carried, carry_row) and
# what world their items come from (world).
module Carrying
  extend ActiveSupport::Concern

  # Rows that still hold something, with their items, by category and name.
  def bag
    carried.includes(:item).where("quantity > 0").sort_by { |row| [ row.item.category, row.item.name ] }
  end

  def quantity_of(item)
    carried.find_by(item: item)&.quantity || 0
  end

  def add_item!(item, count = 1)
    raise Refusal, "#{item.name} is not from #{world.name}" unless item.world_id == world.id

    row = carry_row(item)
    row.update!(quantity: row.quantity + count)
  end

  # Items that do something outside battle (healing, revival).
  def field_items
    bag.select { |row| row.item.consumable? && Battle::Field.usable?(row.item.to_engine(row.quantity)) }
  end

  # Take up to n out (the rows may have changed since).
  def use_items!(item, n)
    row = carried.find_by(item: item)
    row&.update!(quantity: [ row.quantity - n, 0 ].max)
  end

  def take_item!(item, count = 1)
    row = carried.find_by(item: item)
    unless row && row.quantity >= count
      errors.add(:base, "#{item.name} is not in #{bag_name}")
      raise ActiveRecord::RecordInvalid, self
    end

    row.update!(quantity: row.quantity - count)
  end
end
