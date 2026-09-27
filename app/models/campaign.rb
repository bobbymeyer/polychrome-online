# frozen_string_literal: true

# A party's run through a world (docs/HANDOFF.md §4, campaign layer). For
# now it holds the characters, the shared bag and party funds; flags, GM
# diffs and edition pins arrive with build step 8.
class Campaign < ApplicationRecord
  belongs_to :world
  belongs_to :gm, class_name: "User", optional: true
  has_many :characters, dependent: :destroy
  has_many :inventories, dependent: :delete_all
  has_many :battles, class_name: "BattleRecord", dependent: :destroy
  has_many :npcs, dependent: :destroy
  has_many :messages, dependent: :delete_all
  has_many :map_edges, dependent: :destroy
  has_many :map_nodes, dependent: :destroy
  has_many :locations, dependent: :destroy
  has_many :flags, dependent: :delete_all
  has_many :scenes, dependent: :destroy
  belongs_to :current_node, class_name: "MapNode", optional: true

  # Travel encounters use their own seeded RNG, stored here like a battle's.
  before_create { self.rng = Random.new_seed % 2**32 if rng.zero? }

  # The GM's choice of music: a scene's track or silence. Nil follows the
  # scene, so a town sounds like a town and a dungeon like a dungeon.
  MUSIC_CHOICES = (World::MUSIC + %w[silence]).freeze
  normalizes :music, with: ->(value) { value.presence }
  validates :music, inclusion: { in: MUSIC_CHOICES }, allow_nil: true
  after_update_commit :broadcast_music, if: :saved_change_to_music?

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

  # --- shopping ------------------------------------------------------------

  # Buy from a town's stock with party gil. Raises ArgumentError with a
  # reason the table can read.
  def buy!(item, quantity, at:, by:)
    quantity = quantity.to_i.clamp(1, 99)
    raise ArgumentError, "#{at.name} doesn't sell #{item.name}" unless at.stock_items.include?(item)

    cost = item.price * quantity
    transaction do
      reload
      raise ArgumentError, "The party has #{gil} gil; #{quantity} × #{item.name} costs #{cost}" if cost > gil

      update!(gil: gil - cost)
      add_item!(item, quantity)
      messages.create!(kind: "system", body: "#{by} bought #{quantity} × #{item.name} in #{at.name} for #{cost} gil.")
    end
  end

  # Sell from the bag, for half the price.
  def sell!(item, quantity, at:, by:)
    quantity = quantity.to_i.clamp(1, 99)
    transaction do
      row = inventories.find_by(item: item)
      raise ArgumentError, "The bag has #{row&.quantity.to_i} × #{item.name}" if row.nil? || row.quantity < quantity

      row.update!(quantity: row.quantity - quantity)
      earned = item.resale_price * quantity
      update!(gil: gil + earned)
      messages.create!(kind: "system", body: "#{by} sold #{quantity} × #{item.name} in #{at.name} for #{earned} gil.")
    end
  end

  # Sell something a party member is wearing: it comes off, then sells.
  def sell_worn!(character, slot, at:, by:)
    item = character.equipment_slots.find_by(slot: slot)&.item or raise ArgumentError, "#{character.name} isn't wearing anything there"
    transaction do
      character.unequip!(slot)
      sell!(item, 1, at: at, by: by)
    end
  end

  # --- town services -----------------------------------------------------------

  # What a town's services charge, from the party's purse: gil per level of
  # the character served, with a floor. A rumour costs the same for anyone.
  SERVICE_PRICES = { "inn" => [ 5, 10 ], "temple" => [ 20, 50 ], "guild" => [ 0, 30 ] }.freeze
  SERVICE_OFFERS = { "inn" => "a room for the night", "temple" => "a raising", "guild" => "a rumour" }.freeze

  def service_price(kind, character)
    per_level, floor = SERVICE_PRICES.fetch(kind)
    [ per_level * character.level, floor ].max
  end

  # A character pays for a service in the town the party is in:
  #   inn    — a night's rest: full HP and MP (the fallen need a temple)
  #   temple — a fallen character raised, at full HP and MP
  #   guild  — a rumour: the GM owes them one
  def use_service!(kind, character, at:, by:)
    raise ArgumentError, "Not while a battle is on" if battle_on?
    raise ArgumentError, "#{character.name} isn't in this party" unless character.campaign_id == id
    service = at.view.fetch("services", []).find { |s| s["kind"] == kind } or raise ArgumentError, "#{at.name} has no #{kind}"
    case kind
    when "inn"
      raise ArgumentError, "#{character.name} is down: an inn can't help the fallen. A temple can." unless character.conscious?
      raise ArgumentError, "#{character.name} is already rested" if rested?(character)
    when "temple"
      raise ArgumentError, "#{character.name} is still on their feet" if character.conscious?
    end

    cost = service_price(kind, character)
    transaction do
      reload
      raise ArgumentError, "The party has #{gil} gil; #{SERVICE_OFFERS.fetch(kind)} for #{character.name} costs #{cost}" if cost > gil

      update!(gil: gil - cost)
      character.update!(hp: nil, mp: nil) if %w[inn temple].include?(kind)
      messages.create!(kind: "system", body: service_line(kind, character, service, by, cost))
    end
  end

  # Everyone who needs it takes a room, in one payment.
  def rest_at_inn!(at:, by:)
    tired = characters.order(:created_at).select { |c| c.conscious? && !rested?(c) }
    raise ArgumentError, "Everyone standing is already rested" if tired.empty?

    cost = tired.sum { |c| service_price("inn", c) }
    raise ArgumentError, "The party has #{gil} gil; rooms for everyone cost #{cost}" if cost > gil

    transaction { tired.each { |c| use_service!("inn", c, at: at, by: by) } }
  end

  def rested?(character)
    character.current_hp == character.stats["max_hp"] && character.current_mp == character.stats["max_mp"]
  end

  # --- using items outside battle ---------------------------------------------

  def battle_on?
    battles.where(status: "input").exists?
  end

  # The battle the table points at: the newest one still being fought.
  def current_battle
    battles.where(status: "input").order(created_at: :desc, id: :desc).first
  end

  # Items from the bag that do something outside battle (healing, revival).
  def field_items
    bag.select { |row| row.item.consumable? && Battle::Field.usable?(row.item.to_engine(row.quantity)) }
  end

  # One party member uses an item from the bag on another (or themselves),
  # through the engine's own formulas (Battle::Field) and the campaign's RNG.
  def use_item!(item, user:, target:)
    raise ArgumentError, "Not while a battle is on: use it from the battle's Item menu" if battle_on?
    raise ArgumentError, "#{target.name} isn't in this party" unless target.campaign_id == id

    transaction do
      reload
      raise ArgumentError, "There's no #{item.name} in the bag" unless quantity_of(item).positive?

      before = target.current_hp
      hp, _events, next_rng = Battle::Field.use_item(item.to_engine(1), user: user.battle_spec, target: target.battle_spec, rng: rng)
      take_item!(item)
      target.update!(hp: hp)
      update!(rng: next_rng)
      on = target == user ? "" : " on #{target.name}"
      messages.create!(kind: "system", body: "#{user.name} uses #{item.name}#{on}: HP #{before} → #{hp}.")
    end
  rescue Battle::InvalidAction => e
    raise ArgumentError, e.message
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
      origin.location&.leave!
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
      current_node&.location&.leave! unless current_node == node
      update!(current_node: node)
      messages.create!(kind: "system", body: "The party is at #{node.name}.")
    end
    broadcast_map
  end

  def start_pending_encounter!(input_seconds: nil)
    encounter = pending_encounter or raise ArgumentError, "No encounter is waiting"
    standing = characters.order(:created_at).select(&:conscious?)
    raise ArgumentError, "Nobody is standing to fight" if standing.empty?

    battle = BattleRecord.start!(campaign: self, characters: standing, name: encounter["table"],
                                 encounter: encounter["monsters"], input_seconds: input_seconds, boss: encounter["boss"] || false)
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
  # What the party learns about monsters by fighting them (§ Play: weaknesses
  # are found, not given). An element that lands shows how the monster takes
  # it; a status it shrugs off shows it's immune, one that sticks that it
  # isn't; a scan shows everything. Kept per monster, across battles.
  def learn_from!(events, state)
    units = state["units"].index_by { |u| u["id"] }
    learned = known_affinities.deep_dup
    events.each do |event|
      target = units[event["target"]]
      slug = target && target["side"] == "enemy" && target.dig("image", "slug")
      next unless slug

      notes = (learned[slug] ||= {})
      if event["type"] == "scan"
        Battle::ELEMENTS.each { |element| notes[element] = target["elements"].fetch(element, "none") }
        Battle::STATUSES.each { |kind| notes[kind] = target["status_immune"].include?(kind) ? "immune" : "none" }
      elsif event["element"]
        notes[event["element"]] = target["elements"].fetch(event["element"], "none")
      elsif event["type"] == "miss" && event["reason"] == "immune" && event["status"]
        notes[event["status"]] = "immune"
      elsif event["type"] == "status_applied"
        notes[event["status"]] = "none"
      end
    end
    update!(known_affinities: learned) if learned != known_affinities
  end

  # The dungeon the party is inside right now, if any.
  # The kind of scene the party is in, for its music: a dungeon being
  # explored, a town, or the open road.
  def scene
    return "dungeon" if dungeon_in_progress

    current_node&.location&.town? ? "town" : "field"
  end

  # Every game page of the campaign changes track with the GM (stage.js);
  # a battle keeps its own.
  def broadcast_music
    Turbo::StreamsChannel.broadcast_action_to(self, :stage, action: :music, target: "stage",
                                              attributes: { follow: music.nil?, url: world.music_path(music).to_s })
  end

  # The GM calls for a check (Stats::Check): each character rolls against
  # their own stat, from the campaign's RNG, and the table sees it land.
  def check!(characters:, stat:, difficulty:, reason: nil)
    raise ArgumentError, "Pick who's trying" if characters.empty?
    raise ArgumentError, "Pick a stat" unless Stats::Check::STATS.include?(stat)
    raise ArgumentError, "Pick a difficulty" unless Stats::Check::DIFFICULTIES.key?(difficulty)

    transaction do
      rolling = Battle::Rng.new(rng)
      lines = characters.map do |character|
        result = Stats::Check.roll(stat_value: character.stats.fetch(stat), stat: stat, level: character.level,
                                   difficulty: difficulty, rng: rolling)
        label = "#{stat.capitalize} check (#{difficulty})"
        body = "#{character.name}: #{label}#{" to #{reason.strip.sub(/\.\z/, '')}" if reason.present?}. " \
               "#{result['chance']}% · rolled #{result['roll']} · #{result['success'] ? 'Success!' : 'Failure.'}"
        [ body, result.merge("name" => character.name, "stat" => stat, "difficulty" => difficulty) ]
      end
      update!(rng: rolling.state)
      lines.map { |body, data| messages.create!(kind: "system", cue: "check", body: body, data: data) }
    end
  end

  # The choice the table is deciding, if any (Message#settle!).
  def open_choice
    messages.where(kind: "choice", settled: nil).order(:id).last
  end

  def dungeon_in_progress
    location = current_node&.location
    location if location&.dungeon? && location.progress["current"]
  end

  # Everyone back to full, told at the table. Not in the middle of a fight.
  def service_line(kind, character, service, by, cost)
    payer = by == character.name ? character.name : "#{by}, for #{character.name},"
    case kind
    when "inn" then "#{payer} takes a room at #{service['name']} (#{cost} gil). #{character.name} is rested: full HP and MP."
    when "temple" then "#{payer} pays #{cost} gil at #{service['name']}. #{character.name} is raised, whole again."
    when "guild" then "#{payer} buys a rumour at #{service['name']} (#{cost} gil). The GM owes #{character.name} something true."
    end
  end

  def rest!
    raise ArgumentError, "Not while a battle is on" if battle_on?

    transaction do
      characters.update_all(hp: nil, mp: nil)
      messages.create!(kind: "system", body: "The party rests. Everyone is back to full HP and MP.")
    end
  end
end
