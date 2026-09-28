# frozen_string_literal: true

# The party's shared bag: what's in it, putting things in and taking them
# out, and using items outside battle through the engine's own formulas.
module Campaign::Bag
  extend ActiveSupport::Concern

  # Bag rows that still hold something, with their items.
  def bag
    inventories.includes(:item).where("quantity > 0").sort_by { |row| [ row.item.category, row.item.name ] }
  end

  def quantity_of(item)
    inventories.find_by(item: item)&.quantity || 0
  end

  def add_item!(item, count = 1)
    raise Refusal, "#{item.name} is not from #{world.name}" unless item.world_id == world_id

    row = inventories.find_or_create_by!(item: item)
    row.update!(quantity: row.quantity + count)
  end

  # Items from the bag that do something outside battle (healing, revival).
  def field_items
    bag.select { |row| row.item.consumable? && Battle::Field.usable?(row.item.to_engine(row.quantity)) }
  end

  # One party member uses an item from the bag on another (or themselves),
  # through the engine's own formulas (Battle::Field) and the campaign's RNG.
  def use_item!(item, user:, target:)
    raise Refusal, "Not while a battle is on: use it from the battle's Item menu" if battle_on?
    raise Refusal, "#{target.name} isn't in this party" unless target.campaign_id == id

    transaction do
      reload
      raise Refusal, "There's no #{item.name} in the bag" unless quantity_of(item).positive?

      before = target.current_hp
      hp = roll_with do |state|
        healed, _events, next_state = Battle::Field.use_item(item.to_engine(1), user: user.battle_spec, target: target.battle_spec, rng: state,
                                                                                          types: world.type_chart.to_engine)
        [ next_state, healed ]
      end
      take_item!(item)
      target.update!(hp: hp)
      on = target == user ? "" : " on #{target.name}"
      narrate("#{user.name} uses #{item.name}#{on}: HP #{before} → #{hp}.")
    end
  rescue Battle::InvalidAction => e
    raise Refusal, e.message
  end

  # The consumables a battle can use, as the engine wants them.
  def battle_items
    bag.select { |row| row.item.consumable? && row.item.effects.any? }
       .to_h { |row| [ row.item.slug, row.item.to_engine(row.quantity) ] }
  end

  # Take up to n out of the bag (the bag may have changed since).
  def use_items!(item, n)
    row = inventories.find_by(item: item)
    row&.update!(quantity: [ row.quantity - n, 0 ].max)
  end

  def take_item!(item)
    row = inventories.find_by(item: item)
    unless row&.quantity&.positive?
      errors.add(:base, "#{item.name} is not in the bag")
      raise ActiveRecord::RecordInvalid, self
    end

    row.update!(quantity: row.quantity - 1)
  end
end
