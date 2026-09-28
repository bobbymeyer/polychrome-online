# frozen_string_literal: true

# Buying and selling in a town's shop, with the party's money.
module Campaign::Shopping
  extend ActiveSupport::Concern

  # Buy from a town's stock with party gil. Raises Refusal with a
  # reason the table can read.
  def buy!(item, quantity, at:, by:)
    quantity = quantity.to_i.clamp(1, 99)
    raise Refusal, "The shop is shut: #{at.current_mode['name'].downcase}" if at.respond_to?(:service_closed?) && at.service_closed?("shop")
    raise Refusal, "#{at.name} doesn't sell #{item.name}" unless at.stock_items.include?(item)

    cost = (at.respond_to?(:price_of) ? at.price_of(item) : item.price) * quantity
    transaction do
      reload
      raise Refusal, "The party has #{money(gil)}; #{quantity} × #{item.name} costs #{cost}" if cost > gil

      update!(gil: gil - cost)
      add_item!(item, quantity)
      narrate("#{by} bought #{quantity} × #{item.name} in #{at.name} for #{money(cost)}.")
    end
  end

  # Sell from the bag, for half the price.
  def sell!(item, quantity, at:, by:)
    quantity = quantity.to_i.clamp(1, 99)
    raise Refusal, "The shop is shut: #{at.current_mode['name'].downcase}" if at.respond_to?(:service_closed?) && at.service_closed?("shop")
    transaction do
      row = inventories.find_by(item: item)
      raise Refusal, "The bag has #{row&.quantity.to_i} × #{item.name}" if row.nil? || row.quantity < quantity

      row.update!(quantity: row.quantity - quantity)
      earned = (at.respond_to?(:resale_price_of) ? at.resale_price_of(item) : item.resale_price) * quantity
      update!(gil: gil + earned)
      narrate("#{by} sold #{quantity} × #{item.name} in #{at.name} for #{money(earned)}.")
    end
  end

  # Sell something a party member is wearing: it comes off, then sells.
  def sell_worn!(character, slot, at:, by:)
    item = character.equipment_slots.find_by(slot: slot)&.item or raise Refusal, "#{character.name} isn't wearing anything there"
    transaction do
      character.unequip!(slot)
      sell!(item, 1, at: at, by: by)
    end
  end
end
