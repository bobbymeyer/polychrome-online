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
