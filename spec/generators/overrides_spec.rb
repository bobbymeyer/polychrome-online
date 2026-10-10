# frozen_string_literal: true

RSpec.describe Generators::Overrides do
  include GeneratorFixtures

  let(:town) { Generators::Town.generate(seed: 1, template: town_template, tables: town_tables) }
  let(:dungeon) { Generators::Dungeon.generate(seed: 1, template: dungeon_template, encounters: GeneratorFixtures.encounters, tables: dungeon_tables) }

  it "changes nothing without overrides, and never mutates the generated location" do
    frozen = Marshal.load(Marshal.dump(town))
    expect(described_class.apply(town, {})).to eq(town)
    described_class.apply(town, { "name" => "X", "stock" => [] })
    expect(town).to eq(frozen)
  end

  it "renames, replaces stock and keeps pinned services" do
    inn = town["services"].find { |s| s["kind"] == "inn" }
    result = described_class.apply(town, { "name" => "Tule", "stock" => [ "elixir" ],
                                           "pins" => { inn["key"] => inn.merge("name" => "The Pinned Pony") } })
    expect(result["name"]).to eq("Tule")
    expect(result["stock"]).to eq([ "elixir" ])
    expect(result["services"].find { |s| s["kind"] == "inn" }["name"]).to eq("The Pinned Pony")
  end

  it "keeps pins across a reroll" do
    inn = town["services"].find { |s| s["kind"] == "inn" }
    pins = { inn["key"] => inn.merge("name" => "The Pinned Pony") }
    (2..30).each do |seed|
      rerolled = Generators::Town.generate(seed: seed, template: town_template, tables: town_tables)
      expect(described_class.apply(rerolled, { "pins" => pins })["services"].find { |s| s["kind"] == "inn" }["name"]).to eq("The Pinned Pony")
    end
  end

  describe "a dungeon's shape, the GM's" do
    it "moves a room to where it was dragged, the roll's place left behind" do
      room = dungeon["rooms"][1]
      result = described_class.apply(dungeon, { "moved_rooms" => { room["key"] => [ 420, 99 ] } })
      expect(result["rooms"][1].slice("x", "y")).to eq("x" => 420, "y" => 99)
      expect(room.slice("x", "y")).not_to eq("x" => 420, "y" => 99) # the roll is untouched
    end

    it "moves an added room too, which is why moving goes last" do
      anchor = dungeon["rooms"].first["key"]
      added = { "key" => "added-1", "name" => "The vault", "decision" => { "kind" => "event", "text" => "Dust." }, "connect" => anchor }
      result = described_class.apply(dungeon, { "added_rooms" => [ added ], "moved_rooms" => { "added-1" => [ 10, 20 ] } })
      expect(result["rooms"].last.slice("key", "x", "y")).to eq("key" => "added-1", "x" => 10, "y" => 20)
    end

    it "cuts a way by its key" do
      cut = dungeon["paths"].first
      result = described_class.apply(dungeon, { "removed_paths" => [ cut["key"] ] })
      expect(result["paths"].map { |p| p["key"] }).not_to include(cut["key"])
      expect(result["paths"].size).to eq(dungeon["paths"].size - 1)
    end

    it "joins two rooms, marked as the GM's" do
      a, b = dungeon["rooms"].first["key"], dungeon["rooms"].last["key"]
      result = described_class.apply(dungeon, { "added_paths" => [ [ a, b ] ] })
      joined = result["paths"].find { |p| [ p["from"], p["to"] ].sort == [ a, b ].sort }
      expect(joined).to include("added" => true)
      expect(joined["key"]).to eq(described_class.added_path_key(a, b))
    end

    it "won't join a pair the roll already joins, or draw a way to a room it didn't make" do
      joined = dungeon["paths"].first
      result = described_class.apply(dungeon, { "added_paths" => [ [ joined["from"], joined["to"] ], [ "room-0", "room-404" ] ] })
      expect(result["paths"].size).to eq(dungeon["paths"].size)
    end

    it "drops the shape against a layout that no longer has the rooms" do
      # What a reroll would hand it, if reroll! kept the shape (it doesn't).
      shape = { "moved_rooms" => { "room-404" => [ 5, 5 ] }, "added_paths" => [ [ "room-0", "room-404" ] ],
                "removed_paths" => [ "path-room-404-room-405" ] }
      expect { described_class.apply(dungeon, shape) }.not_to raise_error
      expect(described_class.apply(dungeon, shape)["paths"]).to eq(dungeon["paths"])
    end
  end

  it "pins a room's name and decision but not its place in the new layout" do
    room = dungeon["rooms"][1]
    pinned = room.merge("name" => "The Well", "decision" => { "kind" => "event", "text" => "A well." }, "x" => 1, "y" => 1)
    result = described_class.apply(dungeon, { "pins" => { room["key"] => pinned } })
    got = result["rooms"][1]
    expect(got).to include("name" => "The Well", "decision" => { "kind" => "event", "text" => "A well." })
    expect(got.slice("x", "y")).to eq(room.slice("x", "y"))
  end

  it "places a boss" do
    result = described_class.apply(dungeon, { "boss" => { "ogre" => 2 } })
    expect(result["rooms"].find { |r| r["key"] == dungeon["boss"] }["decision"]).to eq("kind" => "boss", "monsters" => { "ogre" => 2 })
  end

  it "adds hand-authored rooms off existing ones, and drops ones whose anchor is gone" do
    added = { "key" => "added-1", "name" => "Secret Library", "decision" => { "kind" => "treasure", "item" => "elixir" }, "connect" => "room-1" }
    orphan = added.merge("key" => "added-2", "connect" => "room-99")
    result = described_class.apply(dungeon, { "added_rooms" => [ added, orphan ] })
    expect(result["rooms"].last).to include("key" => "added-1", "added" => true)
    expect(result["paths"].last).to eq("key" => "path-added-1", "from" => "room-1", "to" => "added-1")
    expect(result["rooms"].map { |r| r["key"] }).not_to include("added-2")
  end
end
