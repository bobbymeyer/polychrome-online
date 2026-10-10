# frozen_string_literal: true

RSpec.describe Generators::Elaboration do
  include GeneratorFixtures

  LEVELS = (1..Generators::Elaboration::MAX_LEVEL).freeze

  def core(seed, template: dungeon_template)
    Generators::Dungeon.generate(seed: seed, template: template,
                                 encounters: GeneratorFixtures.encounters, tables: dungeon_tables)
  end

  def elaborate(dungeon, level, seed)
    described_class.apply(dungeon, level: level, seed: seed,
                          encounters: GeneratorFixtures.encounters, tables: dungeon_tables)
  end

  # A corridor, which is the shape a seeded campaign pins its story onto
  # (Seeds::JustSeven#chain_seed hunts for exactly this).
  def corridor(count = 6)
    rooms = Array.new(count) do |i|
      { "key" => "room-#{i}", "name" => "Room #{i}", "depth" => i, "x" => 80 + i * 150, "y" => 350,
        "decision" => { "kind" => "event", "text" => "Quiet." } }
    end
    paths = (1...count).map { |i| { "key" => "path-#{i - 1}-#{i}", "from" => "room-#{i - 1}", "to" => "room-#{i}" } }
    { "kind" => "dungeon", "name" => "The Sword", "rooms" => rooms, "paths" => paths,
      "entrance" => "room-0", "boss" => "room-#{count - 1}" }
  end

  def graph(dungeon)
    dungeon["paths"].each_with_object(Hash.new { |h, k| h[k] = [] }) do |path, g|
      g[path["from"]] << path["to"]
      g[path["to"]] << path["from"]
    end
  end

  # Breadth-first hop count between two rooms, or nil if unreachable.
  def distance(dungeon, from, to)
    g = graph(dungeon)
    seen = { from => 0 }
    queue = [ from ]
    while (room = queue.shift)
      return seen[room] if room == to

      g[room].each do |other|
        next if seen.key?(other)

        seen[other] = seen[room] + 1
        queue << other
      end
    end
    nil
  end

  # Which core rooms a shortest entrance-to-boss walk goes through, in order.
  def spine(dungeon, core_keys)
    g = graph(dungeon)
    came_by = { dungeon["entrance"] => nil }
    queue = [ dungeon["entrance"] ]
    while (room = queue.shift)
      g[room].each do |other|
        next if came_by.key?(other)

        came_by[other] = room
        queue << other
      end
    end
    walk = []
    room = dungeon["boss"]
    while room
      walk.unshift(room)
      room = came_by[room]
    end
    walk.select { |key| core_keys.include?(key) }
  end

  it "adds nothing at level 0, and leaves a town alone" do
    rolled = core(7)
    expect(elaborate(rolled, 0, 7)).to equal(rolled)
    town = { "kind" => "town", "services" => [] }
    expect(elaborate(town, 5, 7)).to equal(town)
  end

  it "is deterministic, and never mutates what it was given" do
    rolled = core(11)
    frozen = Marshal.load(Marshal.dump(rolled))
    expect(elaborate(rolled, 3, 11)).to eq(elaborate(rolled, 3, 11))
    expect(rolled).to eq(frozen)
    expect(elaborate(rolled, 3, 11)).not_to eq(elaborate(rolled, 3, 12)) # the seed moves it
  end

  it "adds two rooms a step" do
    rolled = corridor
    LEVELS.each do |level|
      grown = elaborate(rolled, level, 5)
      expect(grown["rooms"].size).to eq(rolled["rooms"].size + level * Generators::Elaboration::PER_LEVEL)
      expect(grown["rooms"].count { |r| r["elaborated"] }).to eq(level * Generators::Elaboration::PER_LEVEL)
    end
  end

  it "leaves every core room exactly as it was — name, decision, depth and place" do
    (1..60).each do |seed|
      rolled = core(seed)
      LEVELS.each do |level|
        grown = elaborate(rolled, level, seed)
        rolled["rooms"].each_with_index do |was, i|
          expect(grown["rooms"][i]).to eq(was), "seed #{seed} level #{level}: core room #{was['key']} changed"
        end
        # The core's own ways are untouched too, and still first in the list.
        expect(grown["paths"].first(rolled["paths"].size)).to eq(rolled["paths"])
        expect(grown["entrance"]).to eq(rolled["entrance"])
        expect(grown["boss"]).to eq(rolled["boss"])
      end
    end
  end

  # The invariant, stated two ways.
  it "never shortens the way between two core rooms" do
    (1..60).each do |seed|
      rolled = core(seed)
      keys = rolled["rooms"].map { |r| r["key"] }
      LEVELS.each do |level|
        grown = elaborate(rolled, level, seed)
        keys.combination(2) do |a, b|
          expect(distance(grown, a, b)).to eq(distance(rolled, a, b)),
                                           "seed #{seed} level #{level}: #{a}->#{b} moved from #{distance(rolled, a, b)} to #{distance(grown, a, b)}"
        end
      end
    end
  end

  it "keeps the core rooms of the way down in the same order" do
    (1..40).each do |seed|
      rolled = core(seed)
      keys = rolled["rooms"].map { |r| r["key"] }
      was = spine(rolled, keys)
      LEVELS.each do |level|
        expect(spine(elaborate(rolled, level, seed), keys)).to eq(was), "seed #{seed} level #{level}: the way down changed"
      end
    end
  end

  it "keeps a pinned corridor walkable in order, every level" do
    rolled = corridor
    keys = rolled["rooms"].map { |r| r["key"] }
    LEVELS.each do |level|
      grown = elaborate(rolled, level, 3)
      expect(spine(grown, keys)).to eq(keys) # entrance to boss, through all six, in order
      keys.each_cons(2) { |a, b| expect(distance(grown, a, b)).to eq(1) }
    end
  end

  it "appends as the dial rises, so a pin keeps its room" do
    rolled = core(23)
    LEVELS.each_cons(2) do |lower, higher|
      below = elaborate(rolled, lower, 23)["rooms"]
      above = elaborate(rolled, higher, 23)["rooms"]
      expect(above.first(below.size)).to eq(below), "level #{higher} reshuffled level #{lower}'s rooms"
    end
  end

  it "reaches every added room, and gives each one a decision" do
    (1..40).each do |seed|
      grown = elaborate(core(seed), 5, seed)
      grown["rooms"].select { |r| r["elaborated"] }.each do |room|
        expect(distance(grown, grown["entrance"], room["key"])).not_to be_nil, "#{room['key']} is stranded"
        expect(Generators::Dungeon::DECISIONS).to include(room["decision"]["kind"])
        expect(room["decision"]["kind"]).not_to eq("fork") # forks cost paths; not the dial's business
        expect(room["x"]).to be_between(0, Generators::Dungeon::WIDTH)
        expect(room["y"]).to be_between(0, Generators::Dungeon::HEIGHT)
      end
    end
  end

  it "gives no room more exits than the generator would" do
    (1..40).each do |seed|
      grown = elaborate(core(seed), 5, seed)
      graph(grown).each do |key, others|
        next unless grown["rooms"].any? { |r| r["key"] == key && !r["elaborated"] }

        expect(others.size).to be <= Generators::Dungeon::MAX_EXITS + 1
      end
    end
  end

  it "draws from a stream of its own, leaving the dungeon's roll alone" do
    # The proof that SALT matters: elaborating must not change the core roll,
    # which the core-rooms example above covers, and two dungeons rolled from
    # neighbouring seeds must not elaborate alike.
    expect(elaborate(corridor, 3, 100)["rooms"].drop(6)).not_to eq(elaborate(corridor, 3, 101)["rooms"].drop(6))
  end
end
