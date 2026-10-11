# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/campaigns/just_seven")

# A campaign written ahead of time, in Oda (db/seeds/campaigns/just_seven.rb).
RSpec.describe Seeds::JustSeven do
  before { World.where(slug: "oda").destroy_all }

  let(:gm) { User.create!(name: "Bobby", email_address: "gm@example.com", password: "a-long-enough-password") }
  let!(:campaign) { described_class.run(gm: gm) }
  let(:world) { campaign.world }

  def place(name) = campaign.map_nodes.find_by!(name: name)

  it "adds its guardians, their forms, its masks and its dungeon to Oda's books, all valid" do
    expect(world.slug).to eq("oda")
    expect(world.items.masks.pluck(:slug)).to contain_exactly(*%w[red_mask orange_mask yellow_mask green_mask indigo_mask blue_mask violet_mask])
    slugs = described_class::MONSTERS.keys.map(&:to_s)
    [ world.abilities.where(slug: described_class::ABILITIES.keys.map(&:to_s)), world.items.where(slug: described_class::ITEMS.keys.map(&:to_s)),
      world.monsters.where(slug: slugs), world.location_templates.where(slug: described_class::LOCATION_TEMPLATES.keys.map(&:to_s)),
      world.encounter_tables.where(slug: described_class::ENCOUNTER_TABLES.keys.map(&:to_s)) ].each do |scope|
      scope.each { |entry| expect(entry).to be_valid, "#{entry.class} #{entry.slug}: #{entry.errors.full_messages}" }
    end
    expect(world.monsters.where(slug: slugs).count).to eq(slugs.size)
  end

  it "fights the Sword's water rooms on the field, rising, and the Toad's telegraph breaks" do
    rooms = place("The Sword").location.view["rooms"].index_by { |room| room["name"] }
    expect(rooms["Ankle-deep"].dig("decision", "field", "stages").map { |stage| stage["name"] }).to eq(%w[Ankle-deep Waist-deep Chest-deep])
    expect(rooms["Chest-deep"].dig("decision", "field", "stages").sole["conditions"]).to include(include("kind" => "conduct", "type" => "electric"))
    expect(place("The Cathedral").location.view["rooms"].find { |room| room["name"] == "The barred sanctum" }.dig("decision", "field", "stages").last["name"])
      .to eq("Lights out")

    character = campaign.characters.create!(name: "Ana", job: world.jobs.find_by!(slug: "soldier"), starting_level: 9)
    battle = BattleRecord.start!(campaign: campaign, characters: [ character ], name: "Ankle-deep", encounter: { "moray_eel" => 1 },
                                 field: rooms["Ankle-deep"].dig("decision", "field"))
    expect(battle.state.dig("field", "stages", 0, "name")).to eq("Ankle-deep")
    expect(world.abilities.find_by!(slug: "belly_flash").to_engine).to include("charge" => 1, "interrupt" => 12)
    expect(world.abilities.find_by!(slug: "tide_call").to_engine).to include("again" => true)
  end

  it "holds the hill with die-hards in waves, and Her Song turns the party on itself" do
    hill = place("Founders' Hill").location.view["rooms"].find { |room| room["name"] == "The hill" }["decision"]
    character = campaign.characters.create!(name: "Ana", job: world.jobs.find_by!(slug: "soldier"), starting_level: 12)
    battle = BattleRecord.start!(campaign: campaign, characters: [ character ], name: "The hill", encounter: hill["monsters"], waves: hill["waves"])
    expect(battle.state["units"].count { |u| u["side"] == "enemy" }).to eq(3)
    expect(battle.state["reserves"].map(&:size)).to eq([ 3, 4 ])
    expect(campaign.messages.last.body).to include("and 2 more waves behind them")
    expect(world.abilities.find_by!(slug: "her_song").effects).to include(include("kind" => "rage"))
  end

  it "is made once for a GM: a second run finds it" do
    expect { described_class.run(gm: gm) }.not_to(change { [ Campaign.count, Monster.count, Ability.count ] })
    expect(described_class.run(gm: gm)).to eq(campaign)
  end

  # Each dungeon has a table of its own, themed to it, so the elaboration
  # dial and any un-pinned room it rolls fight the right things. They shared
  # five_rooms, which has no table at all, and the dial could only add
  # treasure, events and traps to them.
  it "gives each dungeon its own encounter table, and none of them a guardian to meet twice" do
    wanted = described_class::DEEPS.to_h { |table, deep| [ deep.fetch(:template).to_s, table.to_s ] }
    described_class::PLACES.each do |name, attrs|
      next unless attrs[:kind] == "dungeon"

      template = place(name).location.location_template
      expect(wanted).to have_key(template.slug), "#{name} is still on #{template.slug}"
      expect(template.encounter_table&.slug).to eq(wanted[template.slug]), name
      # The shape the pins hang on: the room count, the loops and the locks
      # settle the keys and the corridor before a name is drawn, so these
      # must be the same across all seven or a story comes off its rooms.
      expect(template.settings.slice("rooms", "loops", "locks")).to eq("rooms" => [ 4, 6 ], "loops" => 0, "locks" => 0), name
    end
    expect(wanted.values.uniq.size).to eq(7) # one each, not one shared

    # A guardian never turns up as a wandering encounter, and neither do the
    # phase forms or the named antagonists.
    guardians = %w[crab raccoon orchid_mantis cormorant fire_bellied_toad mechanical_bull viper amethyst_7a
                   duel_master smiling_draw investors_second fleet_crasher]
    wandering = world.encounter_tables.where(slug: described_class::ENCOUNTER_TABLES.keys.map(&:to_s))
                     .flat_map { |table| table.entries.flat_map { |entry| entry["monsters"].keys } }.uniq
    expect(wandering & guardians).to be_empty
    expect(world.monsters.where(slug: wandering).count).to eq(wandering.size) # all in the Bestiary
  end

  # The island above ground. Every road the campaign seeded was made without
  # a table, so travelling between the tiers rolled nothing at all.
  it "gives every road a table that matches its ground" do
    wanted = described_class::ROADS.to_h { |from, to, attrs| [ [ from, to ].sort, attrs[:encounters] ] }
    expect(wanted.values).to all(be_present) # no road left quiet

    campaign.map_edges.includes(:from_node, :to_node, :encounter_table).each do |edge|
      slug = wanted.fetch([ edge.from_node.name, edge.to_node.name ].sort)
      expect(edge.encounter_table&.slug).to eq(slug), "#{edge.from_node.name} - #{edge.to_node.name}"
    end
    # The ground each one is on: streets at the waterline, terraces up the
    # slope, the processional at the top, the seabed out to the blade.
    expect(wanted[[ "The Airship Dock", "The Steps" ].sort]).to eq("the_streets")
    expect(wanted[[ "The Reaches", "The Steps" ].sort]).to eq("the_terraces")
    expect(wanted[[ "Founders' Hill", "The Cathedral" ].sort]).to eq("the_processional")
    expect(wanted[[ "The Steps", "The Sword" ].sort]).to eq("the_seabed")
    # And the states are untouched, because they set the odds.
    expect(campaign.map_edges.where(state: "blocked").count).to eq(3)
  end

  it "gives the city its own table, which is what lets the GM call an ambush there" do
    steps = place("The Steps").location
    expect(steps.location_template.slug).to eq("island_city")
    expect(steps.location_template.encounter_table&.slug).to eq("the_streets")

    campaign.update!(current_node: place("The Steps"))
    ambush = Outcome.of("ambush")
    expect(ambush.bites?(campaign)).to be(true) # a hard move with nowhere to come from is no move
    said = ambush.apply!(campaign, by: gm)
    expect(said).to start_with("Encounter!")
    expect(campaign.reload.pending_encounter).to be_present
    theirs = steps.location_template.encounter_table.entries.flat_map { |e| e["monsters"].keys }.uniq
    expect(campaign.pending_encounter["monsters"].keys - theirs).to be_empty
  end

  it "rolls a road's own monsters when the party crosses it" do
    campaign.update!(current_node: place("The Steps"))
    edge = campaign.map_edges.joins(:to_node).find_by(map_nodes: { name: "The Airship Dock" }) ||
           campaign.map_edges.joins(:from_node).find_by(map_nodes: { name: "The Airship Dock" })
    table = edge.encounter_table
    theirs = table.entries.flat_map { |e| e["monsters"].keys }.uniq

    # 25% a crossing on an open road, so cross until one lands.
    rolled = nil
    20.times do
      campaign.update!(current_node: place("The Steps"))
      rolled = campaign.travel!(edge)
      break if rolled
    end
    expect(rolled).to be_present, "no encounter in 20 crossings of a 25% road"
    expect(rolled.keys - theirs).to be_empty
  end

  # The claim the migration rests on: moving a dungeon from five_rooms to its
  # own template leaves the story exactly where it was pinned. The shape is
  # settled from the config and the seed before a name is drawn, and every
  # template carries the same config.
  it "keeps every pinned room and the way down when a dungeon changes template" do
    dungeon = place("The Sword").location
    was = dungeon.view
    generic = world.location_templates.find_by!(slug: "five_rooms")

    dungeon.update!(location_template: generic)
    expect(dungeon.reload.view["rooms"].map { |r| r.slice("key", "name", "decision", "depth") })
      .to eq(was["rooms"].map { |r| r.slice("key", "name", "decision", "depth") })
    expect(dungeon.view["paths"].map { |p| p.slice("key", "from", "to") }).to eq(was["paths"].map { |p| p.slice("key", "from", "to") })
    expect(dungeon.view["entrance"]).to eq(was["entrance"])
    expect(dungeon.view["boss"]).to eq(was["boss"])
  end

  it "fills the elaboration dial's rooms from the dungeon's own table" do
    dungeon = place("The Sword").location
    dungeon.elaborate!(5)
    added = dungeon.reload.view["rooms"].select { |room| room["elaborated"] }
    expect(added).not_to be_empty

    fights = added.select { |room| room["decision"]["kind"] == "encounter" }
    expect(fights).not_to be_empty, "the dial added no fights: #{added.map { |r| r['decision']['kind'] }.tally}"
    theirs = dungeon.location_template.encounter_table.entries.flat_map { |entry| entry["monsters"].keys }.uniq
    expect(fights.flat_map { |room| room["decision"]["monsters"].keys }.uniq - theirs).to be_empty

    # And the six pinned rooms still read as written, at every level.
    written = described_class::PLACES.fetch("The Sword")[:rooms].map { |room| room[:name] }
    expect(dungeon.view["rooms"].reject { |r| r["added"] || r["elaborated"] }.sort_by { |r| r["depth"] }.map { |r| r["name"] }).to eq(written)
  end

  it "starts at the Steps, on its own island, with the GM and the party's money" do
    expect(campaign.gm).to eq(gm)
    expect(campaign.current_node).to eq(place("The Steps"))
    expect(campaign.gil).to eq(Campaign::STARTING_GIL)
    expect(campaign.map_nodes.where(world_place_id: nil).count).to eq(campaign.map_nodes.count) # none of Oda's atlas
    expect(campaign.map_nodes.where(visible: false).pluck(:name)).to contain_exactly("The Airship Dock", "The Dump", "The King's Garden", "The Sky Bridge")
    expect(campaign.map_edges.where(state: "blocked").count).to eq(3)
    expect(campaign.rumours.count).to eq(described_class::RUMOURS.size)
  end

  it "rolls each dungeon as five rooms in order, entrance to guardian to twist" do
    { "The Airship Dock" => "crab", "The Dump" => "raccoon", "The King's Garden" => "orchid_bloom", "The Sky Bridge" => "cormorant",
      "The Sword" => "fire_bellied_toad", "The Cathedral" => "mechanical_bull", "Founders' Hill" => "amethyst_7a" }.each do |name, guardian|
      dungeon = place(name).location
      view = dungeon.view
      written = described_class::PLACES.fetch(name)
      expect(view["name"]).to eq(name)
      rolled = view["rooms"].reject { |room| room["added"] }.sort_by { |room| room["depth"] }
      expect(rolled.map { |room| room["name"] }).to eq(written[:rooms].map { |room| room[:name] }), name
      expect(rolled.map { |room| room["depth"] }).to eq((0...rolled.size).to_a), name
      expect(view["boss"]).to eq(rolled.last["key"])
      expect(rolled.last["decision"]).to eq("kind" => "boss", "monsters" => { guardian => 1 })
      twists = view["rooms"].select { |room| room["added"] }
      expect(twists.map { |room| room["name"] }).to eq(written[:twist].map { |twist| twist[:name] })
      expect(view["paths"].map { |path| path["to"] }).to include(twists.first["key"])
      rolled.map { |room| room["decision"] }.select { |d| d["kind"] == "trap" }.each do |trap|
        expect(Toll.read(trap["text"]).last).to be_empty, trap["text"]
      end
    end
  end

  it "keeps each twist behind its guardian until the guardian falls" do
    party = [ create_character(campaign, name: "Kei", job: world.jobs.find_by!(slug: "courtsword")) ]
    dock = place("The Airship Dock")
    campaign.update!(current_node: dock)
    loc = dock.location
    berth = loc.view["boss"]
    loc.update!(progress: { "current" => berth, "visited" => [ berth ] })
    expect { loc.move_to!("added-1") }.to raise_error(Refusal, /A fight still waits in The deep berth \(Crab\)/)
    campaign.waylay!("The master of The Airship Dock", { "crab" => 1 }, boss: true, location: loc.id, room: berth)
    campaign.wave_off_encounter! # a boss waved off still waits
    expect { loc.reload.move_to!("added-1") }.to raise_error(Refusal)
    campaign.waylay!("The master of The Airship Dock", { "crab" => 1 }, boss: true, location: loc.id, room: berth)
    battle = campaign.start_pending_encounter!
    battle.enemies.each { |unit| battle.apply!({ "type" => "gm_override", "op" => "set_hp", "unit" => unit.id, "value" => 0 }, actor: "gm") unless battle.over? }
    expect(battle.reload.status).to eq("victory")
    loc.reload.move_to!("added-1")
    expect(loc.reload.current_room_key).to eq("added-1")
    expect(party.first).to be_present
  end

  it "speaks in the island's own voice: its people, its shops, and what the GM is offered" do
    steps = place("The Steps")
    town = steps.location.view
    island = described_class::GENERATOR_TABLES
    expect(town["services"].map { |s| s["name"] }).to all(be_in(island[:island_service_names][:entries].map { |e| e[:text] }))
    hooks = island[:island_hooks][:entries].map { |e| e[:text] }
    expect(town["npcs"].filter_map { |npc| npc["hook"] }).to all(be_in(hooks))

    lines = Seeds::JustSeven::GENERATOR_TABLES[:just_seven_arrivals][:entries].map { |e| e[:text].sub("{place}", "The Steps").sub("{coward}", "") }
    campaign.offer_arrival_line!(steps)
    said = campaign.messages.order(:id).last.body[/“(.*)”/, 1]
    expect(lines).to include(said)
    dock = place("The Airship Dock")
    campaign.offer_arrival_line!(dock)
    expect(campaign.messages.order(:id).last.body).to include("something thumps, slow")

    # Not another Oda campaign: its rows ask for flags only The Just Seven sets.
    other = campaign.world.campaigns.create!(name: "High Noon")
    other.set_out!
    other.offer_arrival_line!(other.current_node)
    expect(other.messages.order(:id).last.body).not_to include("sail")
  end

  it "says the open road's journey on each of the roads that start shut" do
    shut = campaign.map_edges.where(state: "blocked")
    expect(shut.map(&:travel_event)).to all(be_present)
    expect(shut.map(&:travel_event).join).not_to match(/shut|barred|only while/i)
  end

  it "puts Amethyst 7A in the Head's last room, and casts the duellists" do
    head = place("Founders' Hill").location
    expect(head.resident_villain.name).to eq("Amethyst 7A")
    expect(campaign.duellists.pluck(:name)).to include("Mob Leader", "The Duel-Master", "The Investors' Second")
  end

  it "writes its clocks, secrets, scenes and flags so the table can use them" do
    signs = campaign.clocks.find_by!(name: "The Seven Signs")
    expect(signs.segments).to eq(7)
    expect(Portent.list(signs.portents).size).to eq(7)
    expect(signs.mode.name).to eq("The chorus")
    expect(campaign.clocks.find_by!(name: "The siege").map_node).to eq(place("The Cathedral"))
    campaign.secrets.each { |secret| expect(secret.clues).not_to be_empty, secret.key }
    expect(campaign.secrets.find_by!(key: "the_plunder").location).to eq(place("The King's Garden").location)
    expect(campaign.scenes.count).to eq(described_class::SCENES.size)
    expect(campaign.scenes.find_by!(name: "Vision: Violet").beats.map(&:text).join).to include("Swirl-Pool")
    expect(campaign.scenes.find_by!(name: "The Seer").beats.find_by!(position: 1).speaker.name).to eq("The Seer")
    expect(campaign.flags.pluck(:key)).to include("combiner_prism", "splitter_prism")
  end

  it "runs every guardian, through its forms, against a party built from the Compendium" do
    base = { max_hp: 150, max_mp: 30, str: 12, mag: 12, vit: 12, spr: 12, agi: 12 }
    party = world.jobs.order(:name).map do |job|
      gear = world.items.select { |item| item.equipment? && !item.mask? && job.equips?(item) }.group_by(&:slot).values.map(&:first)
      stats = Stats::Derivation.derive(base: base, job: job.to_derivation, equipment: gear.map(&:to_equipment), passives: job.passives)
      { id: job.slug, name: job.name, stats: stats, abilities: job.abilities.pluck(:slug) + [ job.signature ] }
    end
    forms = []
    described_class::MONSTERS.each_key do |slug|
      monster = world.monsters.find_by!(slug: slug)
      state = world.battle(seed: monster.id, party: party.sample(4, random: Random.new(monster.id)), monsters: { monster.slug => 1 })
      120.times do
        break unless state["status"] == "input"

        state, events = Battle::Resolver.apply(state, { type: "timeout" })
        forms.concat(events.select { |event| event["type"] == "phase" }.map { |event| event["name"] })
      end
      expect(%w[victory defeat input]).to include(state["status"])
    end
    expect(forms).to include("Orchid Mantis", "Crab (Frenzy)")
  end

  it "cracks the bull open into the Viper, at full health, with no rest between" do
    party = [ { id: "a", name: "A", stats: { max_hp: 900, max_mp: 0, str: 30, mag: 10, vit: 30, spr: 10, agi: 10, atk: 30, def: 20, mdef: 10 } } ]
    state = world.battle(seed: 7, party: party, monsters: { "mechanical_bull" => 1 })
    names = []
    [ 45, 5 ].each do |percent|
      bull = state["units"].find { |unit| unit["side"] == "enemy" }
      bull["hp"] = bull["stats"]["max_hp"] * percent / 100
      state, events = Battle::Resolver.apply(state, { type: "timeout" })
      names.concat(events.select { |event| event["type"] == "phase" }.map { |event| event["name"] })
    end
    expect(names).to eq([ "Mechanical Bull (Overclock)", "Viper" ])
    viper = state["units"].find { |unit| unit["side"] == "enemy" }
    expect(viper["hp"]).to be > viper["stats"]["max_hp"] / 2
  end
end

RSpec.describe "The Just Seven at the table", type: :request do
  before { World.where(slug: "oda").destroy_all }

  it "shows the GM its pages: the campaign, the prep, the table, the moves, the maps, and each dungeon" do
    gm = sign_in_as(make_user("Bobby"))
    campaign = Seeds::JustSeven.run(gm: gm)
    [ campaign_path(campaign), campaign_prep_path(campaign), campaign_table_path(campaign), campaign_moves_path(campaign),
      campaign_maps_path(campaign), campaign_legends_path(campaign) ].each do |path|
      get path
      expect(response).to have_http_status(:ok), path
    end
    campaign.locations.each do |location|
      get location_path(location)
      expect(response).to have_http_status(:ok), location.name
    end
  end

  it "plays the Giant Battle at the table: the crew at their stations, the cast's wearers beside them, Fleet Crasher on the field" do
    gm = sign_in_as(make_user("Bobby"))
    campaign = Seeds::JustSeven.run(gm: gm)
    ana = campaign.characters.create!(name: "Ana", job: campaign.world.jobs.find_by!(slug: "ranger"), starting_level: 13)
    hill = campaign.map_nodes.find_by!(name: "Founders' Hill").location
    landfall = hill.view["rooms"].find { |room| room["name"] == "Landfall" }
    battle = BattleRecord.start!(campaign: campaign, characters: [ ana ], name: "Landfall", encounter: landfall.dig("decision", "monsters"),
                                 crew: landfall.dig("decision", "crew"), boss: true)
    sit_in_battle(battle, "gm")
    get battle_path(battle)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Ana · Ordnance", "The Swordsman · Blade", "Fleet Crasher")
    get battle_panel_path(battle)
    expect(response).to have_http_status(:ok)

    sit_in_battle(battle, ana.battle_unit_id)
    get battle_panel_path(battle)
    expect(page.css("[data-menu-key]").map { |el| el["data-menu-key"] }).to include("Missile Salvo", "Hail Bomb")
  end
end
