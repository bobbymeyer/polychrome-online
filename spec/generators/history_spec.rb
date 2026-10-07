# frozen_string_literal: true

# The Base World's lore, and the names it used to fall back on: a world
# brings its own (World#lore, its names and families tables).
LORE = Generators::Lore::STARTER
GIVEN = %w[Aldo Bryn Cato Dessa Evert Fane Gilda Hob Ismay Joss Kell Lise Mott Nell Osric Petra Quen Roz Seb Tova].freeze
FAMILIES = %w[Vell Marrow Asher Crane Dunmore Hale Pike Rook Thorne Wick Briar Coldwell Fenwick Hargrave Lark Moss Oakes Sallow Tennant Garrow].freeze

RSpec.describe Generators::History do
  include GeneratorFixtures

  let(:places) do
    [ { "key" => "varn", "name" => "Varn", "kind" => "town" }, { "key" => "tule", "name" => "Tule", "kind" => "town" },
      { "key" => "abbey", "name" => "The Drowned Abbey", "kind" => "dungeon" }, { "key" => "mere", "name" => "Greymere", "kind" => "wilds" },
      { "key" => "quarry", "name" => "Old Quarry", "kind" => "dungeon" } ]
  end

  def history(seed, **options)
    described_class.generate(seed: seed, places: places, lore: LORE, given_names: GIVEN, family_names: FAMILIES, **options)
  end

  it "names people by their house alone when the world has no given names, never as Someone" do
    plain = described_class.generate(seed: 3, places: places, lore: LORE, given_names: [], family_names: FAMILIES)
    names = plain["families"].flat_map { |f| Array(f["lineage"]).map { |p| p["name"] } } + plain["places"].values.flat_map { |p| Array(p["lost"]) }
    expect(names).not_to be_empty
    expect(names).to all(satisfy { |name| FAMILIES.include?(name) })
    expect(plain.to_json).not_to include("Someone")
  end

  it "is made of the world's own lore: its trades, what its dungeons were, how they fell, what its families fall out over" do
    undertow = { "trades" => { "stationmaster" => %w[lantern whistle], "teacher" => [] },
                 "pasts" => { "station" => { "rooms" => [ "Ticket Hall", "Platform 2" ], "heart" => "The Last Platform", "keeps" => %w[ticket],
                                             "named" => %w[station line] } },
                 "falls" => { "flood" => { "did" => "went under the tide", "sealed" => "left to the sea", "trace" => "Salt on the timetables.",
                                           "dead" => "who waited for the last train", "town" => "The spring tide came into %s" } },
                 "quarrels" => [ "a seat on the 7:42" ], "betrayals" => [ "told the headmaster" ], "fortunes" => [ "a new branch line" ],
                 "waters" => [ "the harbour" ], "owners" => [] }
    line = [ { "key" => "line", "name" => "The Drowned Line", "kind" => "dungeon" }, { "key" => "town", "name" => "Tsukiura", "kind" => "town" } ]
    run = described_class.generate(seed: 3, places: line, lore: undertow, given_names: %w[Aoi Haruto Mei Sora Yui Ren], family_names: %w[Kurosaki Tsukino Hoshi Mori])
    expect(run["places"]["line"]).to include("was" => "station", "fall" => a_hash_including("kind" => "flood"))
    expect(run["families"].map { |f| f["trade"] } - %w[stationmaster teacher]).to be_empty
    text = run["events"].map { |e| e["text"] }.join(" ")
    expect(text).to include("went under the tide")
    expect(text).not_to match(/horse sold lame|manor|mill race/)
  end

  it "has none of what a world has no lore for, and still runs" do
    run = described_class.generate(seed: 3, places: places, lore: Generators::Lore.empty)
    expect(run["events"].map { |e| e["kind"] }).not_to include("feud", "quarrel", "betrayal", "fire", "flood", "made")
    expect(run["places"]["abbey"]).not_to have_key("was")
    expect(run["families"].map { |f| f["name"] }).to all(start_with("House"))
  end

  it "calls a family a house, and leaves a collective as it is" do
    expect(described_class.house("Vell")).to eq("the Vells")
    expect(described_class.house("Asch", cap: true)).to eq("The Asches")
    expect(described_class.house("the bus company")).to eq("the bus company")
    expect(described_class.house("The Tides", cap: true)).to eq("The Tides")
  end

  it "is reproducible from its seed, and different from another" do
    expect(history(7)).to eq(history(7))
    expect((1..20).map { |s| history(s)["events"] }.uniq.size).to eq(20)
  end

  it "runs oldest first, inside its span, and names only families and places it has" do
    (1..60).each do |seed|
      h = history(seed, years: 120)
      agos = h["events"].map { |e| e["ago"] }
      expect(agos).to eq(agos.sort.reverse)
      expect(agos).to all(be_between(1, 120))
      keys = h["families"].map { |f| f["key"] }
      h["events"].each do |event|
        expect(event["families"] - keys).to be_empty
        expect(event["places"] - places.map { |p| p["key"] }).to be_empty
        expect(event["text"]).to be_a(String).and(end_with("."))
      end
    end
  end

  it "founds every town and builds every dungeon, and every dungeon has fallen by now" do
    (1..60).each do |seed|
      h = history(seed)
      %w[varn tule].each { |key| expect(h["places"][key]).to include("founded", "founder", "family", "rival") }
      %w[abbey quarry].each do |key|
        past = h["places"][key]
        expect(LORE["pasts"]).to have_key(past["was"])
        expect(LORE["falls"].keys + %w[abandoned]).to include(past["fall"]["kind"])
      end
      expect(h["places"].values_at("abbey", "quarry").map { |p| p["was"] }).to eq(%w[abbey mine]) # as their names say
      expect(h["places"]["mere"].keys).to contain_exactly("key", "name", "kind")
      towns = h["events"].select { |e| e["places"] == [ "varn" ] && %w[fire flood plague].include?(e["kind"]) }.map { |e| e["kind"] }
      expect(towns).to eq(towns.uniq) # no town floods twice
      expect(h["feuds"]).not_to be_empty # somewhere a feud is still running
    end
  end

  it "gives families lineages, and heads only while they're still here" do
    (1..40).each do |seed|
      history(seed)["families"].each do |f|
        expect(f["lineage"]).not_to be_empty
        f["gone"] ? expect(f).not_to(have_key("head")) : expect(f["head"]).to(end_with(f["name"]))
      end
    end
  end

  it "keeps what really happened apart from what the table hears" do
    truths = (1..80).flat_map { |s| history(s)["events"].select { |e| e["truth"] } }
    expect(truths).not_to be_empty
    expect(truths.map { |e| e["kind"] }.uniq).to include("betrayal")
    truths.select { |e| e["kind"] == "betrayal" }.each { |e| expect(e["text"]).to include("nobody could say how") }
  end

  it "uses the world's names, and keeps the GM's families through a reroll" do
    surnames = %w[Oddfellow Quint Rask Yarrow Umber Zell]
    h = history(3, family_names: surnames, given_names: %w[Ann Bo Cy Di Ed Flo Gus Hal Ivo Jo Kai Lu])
    expect(h["families"].map { |f| f["name"] } - surnames).to be_empty
    expect(h["families"].map { |f| f["head"] }.compact.map { |n| n.split.first } - %w[Ann Bo Cy Di Ed Flo Gus Hal Ivo Jo Kai Lu]).to be_empty
    kept = [ { "name" => "Vell", "trade" => "smith", "seat" => "tule" } ]
    [ 1, 2, 3 ].each do |seed|
      vell = history(seed, families: kept)["families"].first
      expect(vell).to include("name" => "Vell", "trade" => "smith", "seat" => "tule", "pinned" => true)
    end
  end

  it "remembers what the smiths made and where it was lost" do
    heirlooms = (1..80).flat_map { |s| history(s)["heirlooms"] }
    expect(heirlooms).not_to be_empty
    heirlooms.each { |h| expect(h).to include("name", "maker", "made_for") }
    lost = (1..80).flat_map { |s| history(s)["places"].values.flat_map { |p| Array(p["heirlooms"]) } }
    expect(lost).to all(include("lost_at"))
  end

  it "gives every grudge a reason that reads after “for”" do
    whys = (1..80).flat_map { |s| history(s)["families"].flat_map { |f| f["grudges"].map { |g| g["why"] } } }
    expect(whys).not_to be_empty
    expect(whys).to all(match(/\Athe time they |\Awhat happened at |'s drowning\z/))
  end
end

RSpec.describe Generators::Provenance do
  include GeneratorFixtures

  def dungeon(seed) = Generators::Dungeon.generate(seed: seed, template: dungeon_template, encounters: encounters, tables: dungeon_tables)

  let(:past) do
    { "founded" => 90, "founder" => "Aldo Vell", "family" => "Vell", "was" => "manor", "fall" => { "kind" => "fire", "ago" => 38 },
      "lost" => [ "Pell Vell" ], "heirlooms" => [ { "name" => "the Vell signet", "maker" => "Hob Pike", "made_for" => "Aldo Vell", "lost_at" => "x" } ] }
  end

  it "makes a dungeon what it was, without moving a room or changing a decision's kind" do
    (1..40).each do |seed|
      plain = dungeon(seed)
      made = described_class.apply(plain, past, seed: seed, lore: LORE)
      expect(made).to eq(described_class.apply(plain, past, seed: seed, lore: LORE))
      expect(made["rooms"].map { |r| r.slice("key", "x", "y", "depth") }).to eq(plain["rooms"].map { |r| r.slice("key", "x", "y", "depth") })
      expect(made["rooms"].map { |r| r["decision"]["kind"] }).to eq(plain["rooms"].map { |r| r["decision"]["kind"] })
      expect(made["paths"]).to eq(plain["paths"])

      boss = made["rooms"].find { |r| r["key"] == made["boss"] }
      expect(boss).to include("name" => "Master Bedchamber")
      expect(boss["decision"]["who"]).to eq("Pell Vell, who burned with it")
      expect(made["rooms"].first["name"]).to eq("Entrance")
      manor = LORE["pasts"]["manor"]["rooms"]
      expect(made["rooms"].count { |r| manor.include?(r["name"]) }).to be >= 1
      if (event = made["rooms"].find { |r| r["decision"]["kind"] == "event" })
        expect(made["rooms"].map { |r| r["decision"]["text"] }).to include(LORE["falls"]["fire"]["trace"]), "seed #{seed}: #{event}"
      end
      if (treasure = made["rooms"].find { |r| r["decision"]["kind"] == "treasure" })
        expect(treasure["decision"]["heirloom"]).to eq("name" => "the Vell signet", "maker" => "Hob Pike", "made_for" => "Aldo Vell")
      end
      expect(made["past"]).to eq(past)
    end
  end

  it "rolls a place its own small past when the world's history hasn't given it one" do
    rolled = described_class.past_for(seed: 5, name: "Hollow", kind: "dungeon", lore: LORE, family_names: FAMILIES)
    expect(rolled).to eq(described_class.past_for(seed: 5, name: "Hollow", kind: "dungeon", lore: LORE, family_names: FAMILIES))
    expect(rolled).to include("was", "fall", "founder", "family")
    expect(described_class.past_for(seed: 5, name: "Tule", kind: "town", lore: LORE, family_names: FAMILIES)).to include("founder", "founded", "rival")
  end

  it "says who made a shop's things and who had them, the same each time, each item on its own" do
    town = { "family" => "Vell", "rival" => "Marrow", "makers" => [ { "name" => "Hob Pike", "trade" => "smith" } ] }
    stories = (1..30).map { |seed| described_class.stock(%w[broadsword dagger], town, seed: seed, lore: LORE) }
    expect(stories).to eq((1..30).map { |seed| described_class.stock(%w[broadsword dagger], town, seed: seed, lore: LORE) })
    expect(stories.flat_map(&:values).map { |s| s["maker"] }.compact.uniq).to eq([ "Hob Pike, smith" ])
    expect(stories.flat_map(&:values).map { |s| s["owner"] }.compact.join).to match(/Vell|Marrow/)
    expect(described_class.stock(%w[dagger], town, seed: 4)["dagger"]).to eq(described_class.stock(%w[broadsword dagger], town, seed: 4)["dagger"])
  end
end
