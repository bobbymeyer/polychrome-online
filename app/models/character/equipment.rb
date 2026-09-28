# frozen_string_literal: true

# What a character wears, from the party bag.
module Character::Equipment
  extend ActiveSupport::Concern

  def equipped
    equipment_slots.includes(:item).index_by(&:slot)
  end

  def equipped_items
    (equipment_slots.loaded? ? equipment_slots : equipment_slots.includes(:item)).map(&:item)
  end

  # Put an item from the bag into its slot; whatever was there goes back.
  def equip!(item)
    errors.clear
    unless item.equipment? && job.equips?(item)
      errors.add(:base, "#{job.name} can't equip #{item.name}")
      raise ActiveRecord::RecordInvalid, self
    end

    transaction do
      unequip!(item.slot)
      campaign.take_item!(item)
      equipment_slots.create!(slot: item.slot, item: item)
    end
  end

  def unequip!(slot)
    current = equipment_slots.find_by(slot: slot) or return
    transaction do
      campaign.add_item!(current.item)
      current.destroy!
    end
  end

  private

  # A new character arrives dressed for their job, as in the games: the
  # cheapest thing in the Armory for each slot the job can use. Accessories
  # are earned, not issued.
  def outfit
    return unless starting_gear

    wearable = world.items.where(category: job.equip_categories - [ "accessory" ]).where("price > 0").order(:price, :id)
    wearable.group_by(&:slot).each_value do |choices|
      campaign.add_item!(choices.first)
      equip!(choices.first)
    end
  end
end
