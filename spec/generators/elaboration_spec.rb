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

  def elaborate_with(dungeon, level, seed, variant, tables: dungeon_tables)
    described_class.apply(dungeon, level: level, seed: seed, variant: variant,
                          encounters: GeneratorFixtures.encounters, tables: tables)
  end

  # A world that has given its dungeon both axes of a composed name.
  def composing_tables
    dungeon_tables.merge(
      "room_parts" => %w[pommel\ stair fuller\ groove ballast\ gallery blade\ hollow quillon\ vault
                         lamp\ housing flood\ gate crossguard\ pier].map { |t| { "text" => t } },
      "room_qualities" => %w[flooded collapsed upper lower cold abandoned sealed burnt narrow deep silted
                             forgotten].map { |t| { "text" => t } }
    )
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

  # Location#barred_by holds the party back from anything DEEPER than a room
  # with a fight still waiting in it. So a room past the boss could only be
  # walked once the boss was dead and the dungeon was over -- content nobody
  # would ever play.
  it "never puts a room deeper than the boss" do
    (1..60).each do |seed|
      rolled = core(seed)
      ceiling = rolled["rooms"].find { |r| r["key"] == rolled["boss"] }["depth"]
      LEVELS.each do |level|
        elaborate(rolled, level, seed)["rooms"].select { |r| r["elaborated"] }.each do |room|
          expect(room["depth"]).to be <= ceiling, "seed #{seed} level #{level}: #{room['key']} sits past the boss"
        end
      end
    end
  end

  it "spreads along the way down instead of piling up at the far end" do
    rolled = corridor
    by_depth = Hash.new(0)
    (1..120).each do |seed|
      elaborate(rolled, 5, seed)["rooms"].select { |r| r["elaborated"] }.each { |r| by_depth[r["depth"]] += 1 }
    end
    total = by_depth.values.sum
    # Five depths can take a room (1..5); none of them may hoard a third of them.
    by_depth.each { |depth, n| expect(n).to be < total / 3, "depth #{depth} took #{n} of #{total}" }
    expect(by_depth.keys.sort).to eq([ 1, 2, 3, 4, 5 ])
  end

  # The dial may give a room one more way out than the generator's tree cap
  # (Elaboration::MAX_EXITS) -- it is working around a shape already built,
  # and the generator's limit leaves cramped rolls nowhere to grow. It may
  # not go past that.
  # Dungeon::add_loops doesn't hold itself to MAX_EXITS, so a rolled dungeon
  # can already have a room with five ways out. The dial must not make a room
  # busier than its own cap, but it inherits whatever the roll handed it.
  it "gives no room more ways out than the dial's own cap" do
    (1..60).each do |seed|
      rolled = core(seed)
      was = graph(rolled)
      graph(elaborate(rolled, 5, seed)).each do |key, others|
        expect(others.size).to be <= [ was[key].size, described_class::MAX_EXITS ].max,
                               "seed #{seed}: #{key} went from #{was[key].size} ways to #{others.size}"
      end
    end
  end

  it "fits what it offers on all but the most cramped rolls" do
    added = (1..120).map { |seed| elaborate(core(seed), 5, seed)["rooms"].count { |r| r["elaborated"] } }
    expect(added.sum.to_f / added.size).to be > 9 # offered 10
    expect(added.min).to be > 0 # and the dial always does something
  end

  # The bug this was all about: a seeder hands its dungeons the same seed
  # (Seeds::JustSeven#chain_seed finds the first corridor seed and every one
  # of its templates has the same config), so five of seven came out on seed
  # 7 and elaborated into the identical six rooms in the identical order.
  it "tells two dungeons on the same seed apart by their variant" do
    one = elaborate_with(corridor, 5, 7, "The Sword")
    two = elaborate_with(corridor, 5, 7, "Founders' Hill")
    expect(one["rooms"].drop(6)).not_to eq(two["rooms"].drop(6))
    expect(one["rooms"].drop(6).map { |r| r["name"] }).not_to eq(two["rooms"].drop(6).map { |r| r["name"] })

    # Still deterministic: the same pair gives the same dungeon.
    expect(elaborate_with(corridor, 5, 7, "The Sword")).to eq(one)
  end

  it "composes names from a part and a quality, and never says one twice" do
    grown = elaborate_with(corridor, 5, 3, "The Sword", tables: composing_tables)
    names = grown["rooms"].select { |r| r["elaborated"] }.map { |r| r["name"] }
    expect(names.size).to eq(10)
    expect(names.uniq).to eq(names) # no repeats inside one dungeon
    expect(names).to all(match(/\AThe \w+ /))
    parts = composing_tables["room_parts"].map { |row| row["text"] }
    expect(names).to all(satisfy { |n| parts.any? { |part| n.end_with?(part) } })
  end

  it "falls back to the flat table when a world hasn't given it both" do
    flat = { "rooms" => [ { "text" => "Pithead" }, { "text" => "Cage Shaft" }, { "text" => "Gallery" } ] }
    names = elaborate_with(corridor, 1, 3, "x", tables: flat)["rooms"].select { |r| r["elaborated"] }.map { |r| r["name"] }
    expect(names).to all(satisfy { |n| [ "Pithead", "Cage Shaft", "Gallery" ].include?(n) })

    # Parts without qualities isn't enough to compose, so it stays flat.
    half = flat.merge("room_parts" => [ { "text" => "berth" } ])
    expect(elaborate_with(corridor, 1, 3, "x", tables: half)["rooms"].last["name"]).not_to start_with("The ")
  end

  it "draws from a stream of its own, leaving the dungeon's roll alone" do
    # The proof that SALT matters: elaborating must not change the core roll,
    # which the core-rooms example above covers, and two dungeons rolled from
    # neighbouring seeds must not elaborate alike.
    expect(elaborate(corridor, 3, 100)["rooms"].drop(6)).not_to eq(elaborate(corridor, 3, 101)["rooms"].drop(6))
  end
end
