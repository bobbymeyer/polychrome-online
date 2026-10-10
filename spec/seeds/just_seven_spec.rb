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
      world.monsters.where(slug: slugs), world.location_templates.where(slug: "five_rooms") ].each do |scope|
      scope.each { |entry| expect(entry).to be_valid, "#{entry.class} #{entry.slug}: #{entry.errors.full_messages}" }
    end
    expect(world.monsters.where(slug: slugs).count).to eq(slugs.size)
  end

  it "is made once for a GM: a second run finds it" do
    expect { described_class.run(gm: gm) }.not_to(change { [ Campaign.count, Monster.count, Ability.count ] })
    expect(described_class.run(gm: gm)).to eq(campaign)
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
    expect(campaign.flags.pluck(:key)).to include("combiner_prism", "splitter_prism", "ending")
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
end
