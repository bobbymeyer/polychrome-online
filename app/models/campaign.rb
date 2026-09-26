# frozen_string_literal: true

# A party's run through a world (docs/HANDOFF.md §4, campaign layer). For
# now it holds the characters, the shared bag and party funds; flags, GM
# diffs and edition pins arrive with build step 8.
class Campaign < ApplicationRecord
  belongs_to :world
  has_many :characters, dependent: :destroy
  has_many :inventories, dependent: :delete_all
  has_many :battles, class_name: "BattleRecord", dependent: :destroy

  validates :name, presence: true
  validates :gil, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Bag rows that still hold something, with their items.
  def bag
    inventories.includes(:item).where("quantity > 0").sort_by { |row| [ row.item.category, row.item.name ] }
  end

  def quantity_of(item)
    inventories.find_by(item: item)&.quantity || 0
  end

  def add_item!(item, count = 1)
    raise ArgumentError, "#{item.name} is not from #{world.name}" unless item.world_id == world_id

    row = inventories.find_or_create_by!(item: item)
    row.update!(quantity: row.quantity + count)
  end

  def take_item!(item)
    row = inventories.find_by(item: item)
    unless row&.quantity&.positive?
      errors.add(:base, "#{item.name} is not in the bag")
      raise ActiveRecord::RecordInvalid, self
    end

    row.update!(quantity: row.quantity - 1)
  end

  # An inn: everyone back to full HP and MP, the fallen included.
  def rest!
    characters.update_all(hp: nil, mp: nil)
  end
end
