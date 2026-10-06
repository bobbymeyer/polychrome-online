# frozen_string_literal: true

# The party's chest (Carrying: the inventory rows that are nobody's), and
# what the party does with items as a whole: what each member carries goes
# into battle; found things go in the chest; a member uses what they carry
# outside battle through the engine's own formulas.
module Campaign::Bag
  extend ActiveSupport::Concern
  include Carrying

  def carried = inventories.where(character_id: nil)
  def carry_row(item) = inventories.find_or_create_by!(item: item, character_id: nil)
  def bag_name = "the chest"
  def chest = bag

  # What a new party sets out with, so a bad first fight isn't the end.
  STARTING_BAG = { "potion" => 3, "phoenix_down" => 1 }.freeze

  def pack_starting_bag!
    world.items.where(slug: STARTING_BAG.keys).find_each { |item| add_item!(item, STARTING_BAG.fetch(item.slug)) }
  end

  # Everything the party has between them, the chest and every bag, as
  # { slug => [item, count] }: for what it can give or bring someone. One
  # query, whatever the party's size.
  def party_holdings
    inventories.includes(:item).where("quantity > 0").each_with_object({}) do |row, held|
      held[row.item.slug] = [ row.item, held.dig(row.item.slug, 1).to_i + row.quantity ]
    end
  end

  def party_quantity_of(item) = party_holdings.dig(item.slug, 1).to_i

  # One of it, from the chest first, else from whoever carries it.
  def take_from_party!(item)
    raise Refusal, "#{item.name} is not in the chest or anyone's bag" if take_up_to!(item, 1, chest_first: true).zero?
  end

  # Take up to n out of the party's bags, whoever carries it first, then the
  # chest (a battle's used items, BattleRecord::Settlement): their own before the shared.
  def use_items!(item, n)
    take_up_to!(item, n, chest_first: false)
  end

  # One party member uses an item from their own bag on another (or
  # themselves), through the engine's own formulas (Battle::Field) and the
  # campaign's RNG.
  def use_item!(item, user:, target:)
    raise Refusal, "Not while a battle is on: use it from the battle's Item menu" if battle_on?
    raise Refusal, "#{target.name} isn't in this party" unless target.campaign_id == id

    transaction do
      reload
      raise Refusal, "There's no #{item.name} in #{user.name}'s bag" unless user.quantity_of(item).positive?

      before = target.current_hp
      hp = roll_with do |state|
        healed, _events, next_state = Battle::Field.use_item(item.to_engine(1), user: user.battle_spec, target: target.battle_spec, rng: state,
                                                                                          types: world.type_chart.to_engine)
        [ next_state, healed ]
      end
      user.take_item!(item)
      target.update!(hp: hp)
      on = target == user ? "" : " on #{target.name}"
      narrate("#{user.name} uses #{item.name}#{on}: #{world.word('hp')} #{before} → #{hp}.")
    end
  rescue Battle::InvalidAction => e
    raise Refusal, e.message
  end

  # The consumables a battle can use, as the engine wants them: everything
  # the party has, the chest and every bag, flattened into one count each.
  def battle_items
    party_holdings.filter_map do |slug, (item, count)|
      [ slug, item.to_engine(count) ] if item.consumable? && item.effects.any?
    end.to_h
  end

  private

  # The chest and every member, in the order to take from.
  def holders(chest_first:)
    members = characters.order(:created_at).to_a
    chest_first ? [ self ] + members : members + [ self ]
  end

  # Take up to n of it from the holders in turn; how many came out.
  def take_up_to!(item, n, chest_first:)
    taken = 0
    holders(chest_first: chest_first).each do |holder|
      break unless taken < n

      count = [ holder.quantity_of(item), n - taken ].min
      next unless count.positive?

      holder.take_item!(item, count)
      taken += count
    end
    taken
  end
end
