# frozen_string_literal: true

# A party's run through a world (docs/HANDOFF.md §4, campaign layer). For
# now it holds the characters, the shared bag and party funds; flags, GM
# diffs and edition pins arrive with build step 8.
class Campaign < ApplicationRecord
  belongs_to :world
  has_many :characters, dependent: :destroy
  has_many :inventories, dependent: :delete_all
  has_many :battles, class_name: "BattleRecord", dependent: :destroy
  has_many :npcs, dependent: :destroy
  has_many :messages, dependent: :delete_all
  has_many :map_edges, dependent: :destroy
  has_many :map_nodes, dependent: :destroy
  has_many :locations, dependent: :destroy
  has_many :flags, dependent: :delete_all
  belongs_to :current_node, class_name: "MapNode", optional: true

  # Travel encounters use their own seeded RNG, stored here like a battle's.
  before_create { self.rng = Random.new_seed % 2**32 if rng.zero? }

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

  # --- the pointcrawl map (§7) -----------------------------------------------

  # Move the party along an edge from where it stands. Arriving reveals the
  # destination. If the edge has an encounter table, roll on it with the
  # campaign's RNG; a hit waits as the pending encounter for the GM to start
  # or wave off. Everything is announced at the table.
  def travel!(edge)
    rolled = nil
    with_lock do
      raise ArgumentError, "The party isn't on the map" unless current_node
      raise ArgumentError, "That path doesn't start here" unless edge.touches?(current_node)
      raise ArgumentError, "That path is blocked" if edge.blocked?

      origin = current_node
      destination = edge.other_end(origin)
      if edge.encounter_table
        self.rng, rolled = Pointcrawl::Encounters.roll(rng, edge.encounter_table.entries, edge.state)
      end
      destination.update!(visible: true)
      self.current_node = destination
      self.pending_encounter = rolled && { "table" => edge.encounter_table.name, "monsters" => rolled }
      save!

      messages.create!(kind: "system", body: "The party travels from #{origin.name} to #{destination.name}.")
      messages.create!(body: edge.travel_event) if edge.travel_event
      messages.create!(kind: "system", body: "Encounter! #{describe_encounter(rolled)}.") if rolled
    end
    broadcast_map
    rolled
  end

  # GM: put the party somewhere directly (and reveal it).
  def place_party!(node)
    transaction do
      node.update!(visible: true)
      update!(current_node: node)
      messages.create!(kind: "system", body: "The party is at #{node.name}.")
    end
    broadcast_map
  end

  def start_pending_encounter!
    encounter = pending_encounter or raise ArgumentError, "No encounter is waiting"
    standing = characters.order(:created_at).select(&:conscious?)
    raise ArgumentError, "Nobody is standing to fight" if standing.empty?

    battle = BattleRecord.start!(campaign: self, characters: standing, name: encounter["table"],
                                 encounter: encounter["monsters"])
    update!(pending_encounter: nil)
    battle
  end

  def wave_off_encounter!
    return unless pending_encounter

    update!(pending_encounter: nil)
    messages.create!(kind: "system", body: "The GM waves off the encounter.")
  end

  def describe_encounter(monsters)
    names = world.monsters.where(slug: monsters.keys).index_by(&:slug)
    monsters.map { |slug, count| "#{count} × #{names[slug]&.name || slug}" }.to_sentence
  end

  # Re-render the map for each audience. Players get a separately rendered
  # map without hidden places, on their own stream, so a hidden node never
  # reaches their browser.
  def broadcast_map
    { false => :map, true => :map_gm }.each do |gm, stream|
      broadcast_replace_to self, stream, target: "map_canvas", partial: "maps/canvas", locals: { campaign: self, gm: gm }
    end
  end

  # An inn: everyone back to full HP and MP, the fallen included.
  def rest!
    characters.update_all(hp: nil, mp: nil)
  end
end
