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

  describe "locks and keys" do
    let(:flavours) { [ { "text" => "Altar", "key" => "Goat's skull" }, { "text" => "Portal", "key" => "Blue crystal" } ] }

    def locked(seed, locks: 2)
      dungeon(seed, template: dungeon_template.merge("locks" => locks), tables: dungeon_tables.merge("locks" => flavours))
    end

    # Rooms reachable from the entrance through every path not still locked.
    def reach(d, closed)
      g = Hash.new { |h, k| h[k] = [] }
      d["paths"].each do |p|
        next if p["lock"] && closed.include?(p["lock"]["id"])

        g[p["from"]] << p["to"]
        g[p["to"]] << p["from"]
      end
      seen = [ d["entrance"] ]
      queue = [ d["entrance"] ]
      while (room = queue.shift)
        (g[room] - seen).each { |n| seen << n; queue << n }
      end
      seen
    end

    it "can always be solved: each key is reachable before its lock, and the boss only after all of them" do
      (1..300).each do |seed|
        d = locked(seed)
        locks = d["paths"].filter_map { |p| p["lock"] }.uniq.sort_by { |l| l["id"] }
        closed = locks.map { |l| l["id"] }
        expect(reach(d, closed)).not_to include(d["boss"]) if locks.any?
        locks.each do |lock|
          key_room = d["rooms"].find { |r| r["decision"] == { "kind" => "key", "lock" => lock["id"], "name" => lock["key_name"] } }
          expect(key_room).not_to be_nil
          expect(reach(d, closed)).to include(key_room["key"]), "seed #{seed}: #{lock['id']}'s key is locked away"
          expect([ d["entrance"], d["boss"] ]).not_to include(key_room["key"])
          closed.delete(lock["id"])
        end
        expect(reach(d, closed)).to include(d["boss"])
      end
    end

    it "takes its flavour from the locks table, and usually places the locks asked for" do
      placed = (1..100).map { |seed| locked(seed).fetch("paths").filter_map { |p| p.dig("lock", "id") }.uniq.size }
      expect(placed.max).to eq(2)
      expect(placed.min).to eq(1) # some dungeons only have room for one
      expect(placed.sum / 100.0).to be > 1
      lock = (1..100).lazy.map { |seed| locked(seed, locks: 1)["paths"].find { |p| p["lock"] } }.find(&:itself)["lock"]
      expect([ [ "Altar", "Goat's skull" ], [ "Portal", "Blue crystal" ] ]).to include([ lock["name"], lock["key_name"] ])
    end

    it "rolls a dungeon without locks exactly as before" do
      expect(dungeon(5, template: dungeon_template.merge("locks" => 0))).to eq(dungeon(5))
    end
  end

  it "doesn't repeat an event until its table runs out" do
    dungeons.each do |d|
      texts = d["rooms"].filter_map { |room| room["decision"]["text"] if room["decision"]["kind"] == "event" }
      expect(texts.uniq.size).to eq([ texts.size, dungeon_tables["room_events"].size ].min)
    end
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
      expect(d["paths"].count { |p| p["cost"] && [ p["from"], p["to"] ].include?(room["key"]) && p["cost"] == room["decision"]["text"] }).to eq(1)
    end
  end

  describe "a fork's cost buys something" do
    def distances(g, from)
      dist = { from => 0 }
      queue = [ from ]
      while (room = queue.shift)
        g[room].each { |n| dist[n] ||= (queue << n; dist[room] + 1) }
      end
      dist
    end

    let(:costly) do
      dungeons.flat_map do |d|
        d["rooms"].select { |r| r["decision"]["kind"] == "fork" }.map { |r| [ d, r, d["paths"].find { |p| p["key"] == r["decision"]["costly_path"] } ] }
      end
    end

    it "makes the costly way a real shortcut to the boss, with another way round" do
      shortcuts = costly.select { |_, _, path| path["gain"] == "shortcut" }
      expect(shortcuts).not_to be_empty
      shortcuts.each do |d, room, path|
        g = graph(d)
        through = ([ path["from"], path["to"] ] - [ room["key"] ]).first
        to_boss = distances(g, d["boss"])
        others = g[room["key"]].reject { |n| n == through }.map { |n| to_boss.fetch(n, Float::INFINITY) }
        expect(to_boss[through]).to be < others.min
        without = g.transform_values { |ns| ns.dup }
        without[room["key"]].delete(through)
        without[through].delete(room["key"])
        expect(distances(without, d["entrance"])).to include(d["boss"])
      end
    end

    it "otherwise puts treasure down the costly way" do
      hoards = costly.select { |_, _, path| path["gain"] == "treasure" }
      expect(hoards).not_to be_empty
      hoards.each do |d, room, path|
        through = ([ path["from"], path["to"] ] - [ room["key"] ]).first
        g = graph(d).transform_values { |ns| ns - [ room["key"] ] }
        side = distances(g, through).keys
        expect(side.any? { |key| d["rooms"].find { |r| r["key"] == key }["decision"]["kind"] == "treasure" }).to be true
      end
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
