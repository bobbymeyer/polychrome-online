# frozen_string_literal: true

RSpec.describe Generators::Town do
  include GeneratorFixtures

  def town(seed, template: town_template, tables: town_tables)
    described_class.generate(seed: seed, template: template, tables: tables)
  end

  it "is deterministic: same seed, same town; different seed, different town" do
    expect(town(5)).to eq(town(5))
    expect((1..20).map { |s| town(s) }.uniq.size).to be > 15
  end

  it "always has the services the template guarantees, and rolls the rest" do
    towns = (1..200).map { |s| town(s) }
    towns.each { |t| expect(t["services"].map { |s| s["kind"] }).to include("inn", "shop") }
    guilds = towns.count { |t| t["services"].any? { |s| s["kind"] == "guild" } }
    expect(guilds).to be_within(30).of(100)
  end

  it "staffs every service and gives townsfolk distinct names and hooks" do
    (1..100).each do |seed|
      t = town(seed)
      keepers = t["npcs"].filter_map { |n| n["service"] }
      expect(keepers).to match_array(t["services"].map { |s| s["kind"] })
      expect(t["npcs"].size).to be_between([ 3, t["services"].size ].max, 6)
      expect(t["npcs"].map { |n| n["name"] }.uniq.size).to eq(t["npcs"].size)
      expect(t["npcs"].map { |n| n["key"] }).to eq((0...t["npcs"].size).map { |i| "npc-#{i}" })
      expect(t["npcs"]).to all(include("hook"))
    end
  end

  it "stocks the shop from the stock table, without repeats" do
    (1..100).each do |seed|
      stock = town(seed)["stock"]
      expect(stock.size).to be_between(3, 5)
      expect(stock).to eq(stock.uniq)
      expect(town_tables["stock"].map { |e| e["item"] }).to include(*stock)
    end
  end

  it "has no stock without a shop" do
    expect(town(1, template: town_template.merge("services" => { "inn" => 100 }))["stock"]).to eq([])
  end

  it "builds a skyline with one building per service, from the archetypes" do
    (1..100).each do |seed|
      t = town(seed)
      skyline = t["skyline"]
      expect(skyline.size).to be_between(7, 11)
      expect(skyline.filter_map { |b| b["service"] }).to match_array(t["services"].map { |s| s["kind"] })
      expect(skyline).to all(include("width", "height", "roof", "key"))
      skyline.each { |b| expect(Generators::Town::ROOFS).to include(b["roof"]) }
    end
  end

  it "copes with empty tables" do
    t = town(1, tables: {})
    expect(t["name"]).to eq("Nameless Town")
    expect(t["npcs"].first["name"]).to start_with("Stranger")
  end
end
