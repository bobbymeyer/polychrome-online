# frozen_string_literal: true

# What a character carries (their own bag, Carrying) and wears, and the
# party's chest they take from and put into.
module Character::Equipment
  extend ActiveSupport::Concern
  include Carrying

  included do
    has_many :inventories, dependent: :destroy
  end

  def carried = inventories
  def carry_row(item) = inventories.find_or_create_by!(item: item, campaign: campaign)
  def bag_name = "#{name}'s bag"

  def equipped
    equipment_slots.includes(:item).index_by(&:slot)
  end

  def equipped_items
    (equipment_slots.loaded? ? equipment_slots : equipment_slots.includes(:item)).map(&:item)
  end

  # Put an item from their bag into its slot; whatever was there goes back.
  def equip!(item)
    raise Refusal, "#{job.name} can't equip #{item.name}" unless item.equipment? && job.equips?(item)

    transaction do
      unequip!(item.slot)
      take_item!(item)
      equipment_slots.create!(slot: item.slot, item: item)
    end
  end

  def unequip!(slot)
    current = equipment_slots.find_by(slot: slot) or return
    transaction do
      add_item!(current.item)
      current.destroy!
    end
  end

  # --- The chest -------------------------------------------------------------

  def take_from_chest!(item, count = 1)
    count = count.to_i.clamp(1, 99)
    transaction do
      campaign.take_item!(item, count)
      add_item!(item, count)
    end
  end

  def put_in_chest!(item, count = 1)
    count = count.to_i.clamp(1, 99)
    transaction do
      take_item!(item, count)
      campaign.add_item!(item, count)
    end
  end

  # Leaving the party: what they wear and carry goes to the chest.
  def leave_gear_in_chest!
    transaction do
      equipment_slots.includes(:item).each { |slot| unequip!(slot.slot) }
      bag.each { |row| put_in_chest!(row.item, row.quantity) }
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
      add_item!(choices.first)
      equip!(choices.first)
    end
  end
end
