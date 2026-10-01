# frozen_string_literal: true

RSpec.describe Generators::Report do
  include GeneratorFixtures

  describe "a town template" do
    let(:report) { described_class.town(template: town_template, tables: town_tables, seeds: 1..50) }

    it "counts sizes and shares over its rolls" do
      expect(report["rolls"]).to eq(50)
      min, mean, max = report["sizes"]["townsfolk"]
      expect(min).to be >= 3
      expect(max).to be <= 6
      expect(mean).to be_between(min, max)
      expect(report["shares"]["services"]).to include("inn" => 100, "shop" => 100)
    end

    it "says which rows came up, and which never did" do
      names = report["tables"]["town_names"]
      expect(names["rows"]).to eq(3)
      expect(names["drawn"].values.sum).to eq(50)
      expect(names["never"]).to be_empty

      unseen = described_class.town(template: town_template, tables: town_tables.merge("stock" => town_tables["stock"] + [ { "item" => "excalibur", "weight" => 0 } ]),
                                    seeds: 1..20)
      expect(unseen["tables"]["stock"]).to include("rows" => 8, "never" => [ "excalibur" ])
      expect(unseen["tables"]["stock"]["drawn"]).to include("excalibur" => 0)
    end

    it "finds the stand-ins when a table is missing" do
      bare = described_class.town(template: town_template, tables: town_tables.except("names", "town_names"), seeds: 1..10)
      expect(bare["placeholders"]).to include("town name" => 100, "townsperson's name" => 100, "hook" => 0)
      expect(bare["tables"]).not_to have_key("names")
    end
  end

  describe "a dungeon template" do
    let(:report) do
      described_class.dungeon(template: dungeon_template.merge("locks" => 2), tables: dungeon_tables.merge("locks" => [ { "text" => "Altar", "key" => "Skull" } ]),
                              encounters: GeneratorFixtures.encounters, seeds: 1..60)
    end

    it "counts rooms, decisions and what forks buy" do
      expect(report["sizes"]["rooms"].first).to be >= 6
      expect(report["shares"]["decisions"].keys).to include("encounter", "boss")
      expect(report["shares"]["decisions"]["boss"]).to be_positive
      expect(report["shares"]["forks"].keys - [ "shortcut", "treasure", "buys nothing" ]).to be_empty
      expect(report["shares"]["fork costs"].keys - [ "the game takes", "the GM plays out" ]).to be_empty
    end

    it "says how many locks found no place" do
      expect(report["locks"]["asked"]).to eq(120)
      expect(report["locks"]["placed"]).to be_between(1, 120)
    end

    it "says what dungeons were and how they fell, from the world's lore, and which lore never comes up" do
      lore = Generators::Lore::STARTER
      told = described_class.dungeon(template: dungeon_template, tables: dungeon_tables, encounters: GeneratorFixtures.encounters, seeds: 1..60,
                                     lore: lore, family_names: %w[Vell Marrow])
      expect(told["shares"]["what they were"].keys - lore["pasts"].keys - [ "nothing in particular" ]).to be_empty
      expect(told["shares"]["how they fell"].keys - lore["falls"].keys - [ "still standing" ]).to be_empty
      expect(told["lore"]["pasts"]).to eq(lore["pasts"].keys - told["shares"]["what they were"].keys)
      expect(report["shares"]["what they were"]).to eq("nothing in particular" => 100)
    end

    it "counts treasure rows by item or money" do
      expect(report["tables"]["treasure"]["drawn"].keys).to contain_exactly("potion", "phoenix_down")
    end
  end
end
