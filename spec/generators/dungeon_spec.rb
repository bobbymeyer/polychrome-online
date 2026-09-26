# frozen_string_literal: true

RSpec.describe Generators::Dungeon do
  include GeneratorFixtures

  def dungeon(seed, template: dungeon_template, encounters: GeneratorFixtures.encounters, tables: dungeon_tables)
    described_class.generate(seed: seed, template: template, encounters: encounters, tables: tables)
  end

  def dungeons
    @dungeons ||= (1..300).map { |seed| dungeon(seed) }
  end

  def graph(d)
    d["paths"].each_with_object(Hash.new { |h, k| h[k] = [] }) do |p, g|
      g[p["from"]] << p["to"]
      g[p["to"]] << p["from"]
    end
  end

  it "is deterministic" do
    expect(dungeon(9)).to eq(dungeon(9))
    expect(dungeon(9)).not_to eq(dungeon(10))
  end

  # §7: "Every room must carry a decision."
  it "gives every room a decision, and every decision what it needs" do
    dungeons.each do |d|
      d["rooms"].each do |room|
        decision = room["decision"]
        expect(Generators::Dungeon::DECISIONS).to include(decision["kind"])
        case decision["kind"]
        when "encounter", "boss" then expect(decision["monsters"]).to be_a(Hash).and(be_any)
        when "treasure" then expect(%w[potion phoenix_down]).to include(decision["item"])
        when "event", "fork" then expect(decision["text"]).to be_a(String).and(satisfy { |t| !t.empty? })
        end
      end
    end
  end

  it "connects every room to the entrance" do
    dungeons.each do |d|
      g = graph(d)
      seen = [ d["entrance"] ]
      queue = seen.dup
      while (room = queue.shift)
        (g[room] - seen).each do |n|
          seen << n
          queue << n
        end
      end
      expect(seen).to match_array(d["rooms"].map { |r| r["key"] })
    end
  end

  it "branches and loops" do
    loops = dungeons.count { |d| d["paths"].size >= d["rooms"].size }
    branches = dungeons.count { |d| graph(d).values.any? { |n| n.size >= 3 } }
    expect(loops).to be > 250
    expect(branches).to be > 250
  end

  it "puts the boss in the deepest room and makes it the only boss" do
    dungeons.each do |d|
      boss = d["rooms"].find { |r| r["key"] == d["boss"] }
      expect(boss["depth"]).to eq(d["rooms"].map { |r| r["depth"] }.max)
      expect(d["rooms"].count { |r| r["decision"]["kind"] == "boss" }).to eq(1)
    end
  end

  it "uses the template's boss when there is one" do
    boss = dungeon(1, template: dungeon_template.merge("boss" => { "ogre" => 1 }))["rooms"].find { |r| r["decision"]["kind"] == "boss" }
    expect(boss["decision"]).to eq("kind" => "boss", "monsters" => { "ogre" => 1 })
  end

  it "only puts forks where there is a choice, and marks the costly path" do
    forks = dungeons.flat_map { |d| d["rooms"].select { |r| r["decision"]["kind"] == "fork" }.map { |r| [ d, r ] } }
    expect(forks).not_to be_empty
    forks.each do |d, room|
      path = d["paths"].find { |p| p["key"] == room["decision"]["costly_path"] }
      expect([ path["from"], path["to"] ]).to include(room["key"])
      expect(path["cost"]).to eq(room["decision"]["text"])
      expect(graph(d)[room["key"]].size).to be >= 2
    end
  end

  it "lays rooms out inside the floorplan, deeper to the right" do
    dungeons.each do |d|
      d["rooms"].each do |r|
        expect(r["x"]).to be_between(0, Generators::Dungeon::WIDTH)
        expect(r["y"]).to be_between(0, Generators::Dungeon::HEIGHT)
      end
      expect(d["rooms"].sort_by { |r| [ r["depth"], r["x"] ] }.map { |r| r["x"] }).to eq(d["rooms"].map { |r| r["x"] }.sort)
    end
  end

  it "falls back to events when it has nothing else to offer" do
    kinds = dungeon(3, encounters: [], tables: {})["rooms"].map { |r| r["decision"]["kind"] }.uniq
    expect(kinds - %w[event fork boss]).to be_empty
  end
end
