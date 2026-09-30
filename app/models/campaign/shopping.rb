# frozen_string_literal: true

# Buying and selling in a town's shop, with the party's money.
module Campaign::Shopping
  extend ActiveSupport::Concern

  # Buy from a town's stock with party gil. Raises Refusal with a
  # reason the table can read.
  def buy!(item, quantity, at:, by:)
    quantity = quantity.to_i.clamp(1, 99)
    raise Refusal, "The shop is shut: #{at.shut_by('shop').name.downcase}" if at.shut_by("shop")
    raise Refusal, "#{at.name} doesn't sell #{item.name}" unless at.stock_items.include?(item)
    refuse_if_shunned!(at)

    cost = at.price_of(item) * quantity
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
    raise Refusal, "The shop is shut: #{at.shut_by('shop').name.downcase}" if at.shut_by("shop")
    refuse_if_shunned!(at)
    transaction do
      row = inventories.find_by(item: item)
      raise Refusal, "The bag has #{row&.quantity.to_i} × #{item.name}" if row.nil? || row.quantity < quantity

      row.update!(quantity: row.quantity - quantity)
      earned = at.resale_price_of(item) * quantity
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

  private

  def refuse_if_shunned!(at)
    raise Refusal, "Nobody in #{at.name} will deal with the party." if at.shuns_party?
  end
end
