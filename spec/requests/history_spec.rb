# frozen_string_literal: true

require "rails_helper"

RSpec.describe "A setting's pocket history (Chronicle) and where things came from", type: :request do
  let!(:world) { base_world_without_atlas } # draws its own map
  let(:village) { world.location_templates.find_by!(slug: "village") }
  let(:crypt) { world.location_templates.find_by!(kind: "dungeon") }
  let!(:varn) { world.world_places.create!(name: "Varn", kind: "town", x: 200, y: 200, known: true, location_template: village) }
  let!(:tule) { world.world_places.create!(name: "Tule", kind: "town", x: 400, y: 300, known: true, location_template: village) }
  let!(:abbey) { world.world_places.create!(name: "The Drowned Abbey", kind: "dungeon", x: 600, y: 200, location_template: crypt) }
  let!(:mere) { world.world_places.create!(name: "Greymere", kind: "wilds", x: 700, y: 500) }

  def chronicle = Chronicle.new(world.reload)

  it "is rolled over the atlas, rerolled until it's right, and keeps the families the GM keeps" do
    get world_history_path(world)
    expect(response).to have_http_status(:ok)
    first = chronicle.generated
    expect(response.body).to include("What happened", first["events"].first["text"].split(".").first.sub("'", "&#39;"))
    expect(chronicle.generated).to eq(first) # the same from the same seed

    keep = first["families"].first
    patch world_history_path(world), params: { keep: keep["key"] }
    patch world_history_path(world), params: { reroll: 1 }
    rerolled = chronicle.generated
    expect(rerolled["events"]).not_to eq(first["events"])
    expect(rerolled["families"].first).to include("name" => keep["name"], "trade" => keep["trade"], "pinned" => true)

    patch world_history_path(world), params: { years: 60 }
    expect(chronicle.years).to eq(60)
    patch world_history_path(world), params: { let_go: keep["name"] }
    expect(chronicle.kept).to be_empty
  end

  it "writes into the canon: codex pages, the living heads, every place's past and the running feuds as fronts" do
    history = chronicle.generated
    post world_history_path(world)
    expect(flash[:notice]).to start_with("Written in:")

    page = world.codex_entries.find_by!(title: "The last 100 years")
    expect(page).to have_attributes(category: "History", public: true, history_key: "history")
    expect(page.body).to include(history["events"].first["text"])
    families = history["families"]
    expect(world.codex_entries.where(category: "People").pluck(:title)).to match_array(families.map { |f| "The #{f['name']} family" })
    heads = families.filter_map { |f| f["head"] }
    expect(world.world_figures.pluck(:name)).to match_array(heads)
    seated = families.find { |f| f["head"] && f["seat"] }
    expect(world.world_figures.find_by!(name: seated["head"]).world_place).to eq(chronicle.place_for(seated["seat"]))

    expect(varn.reload.past).to include("founder", "founded", "family")
    expect(abbey.reload.past).to include("was", "fall")
    expect(mere.reload.past).to eq({})
    feud = history["feuds"].first
    front = world.world_fronts.find_by!(name: "The #{feud['names'].join('–')} feud")
    expect(front.clocks.sole["name"]).to end_with("comes to blood")

    # Written in again: the same, and what the GM changed stays theirs.
    mine = world.codex_entries.find_by!(title: "The #{families.first['name']} family")
    patch world_codex_entry_path(world, mine), params: { codex_entry: { body: "Mine now." } }
    # Touched or saved by anything but the GM's form, it's still the history's.
    travel(1.minute) { world.world_figures.where.not(history_key: nil).find_each(&:touch) }
    world.world_fronts.where.not(history_key: nil).find_each { |f| f.update!(description: "#{f.description} ") }
    post world_history_path(world)
    expect(world.codex_entries.find_by!(title: "The #{families.first['name']} family").body).to eq("Mine now.")
    expect(world.codex_entries.where(title: "The last 100 years").count).to eq(1)

    delete world_history_path(world)
    expect(world.codex_entries.pluck(:title)).to eq([ "The #{families.first['name']} family" ])
    expect(world.world_figures).to be_empty
    expect(world.world_fronts).to be_empty
    expect(varn.reload.past).to eq({})
    expect(chronicle).not_to be_written
  end

  it "shapes a campaign's places: a town's founder and feud, a dungeon's rooms, boss and treasure from what it was" do
    post world_history_path(world)
    abbey.update!(past_form: { "was" => "manor", "family" => "Vell", "founder" => "Aldo Vell", "founded" => "90",
                               "fall_kind" => "fire", "fall_ago" => "38", "lost" => "Pell Vell" })
    expect(abbey.reload.past).to include("was" => "manor", "fall" => { "kind" => "fire", "ago" => 38 }, "lost" => [ "Pell Vell" ], "edited" => true)

    post world_campaigns_path(world), params: { campaign: { name: "Rust" } }
    campaign = world.campaigns.find_by!(name: "Rust")
    post campaign_table_seat_path(campaign), params: { seat: "gm" }
    dungeon = campaign.locations.find { |l| l.dungeon? }
    view = dungeon.view
    boss = view["rooms"].find { |r| r["key"] == view["boss"] }
    expect(boss).to include("name" => "Master Bedchamber")
    expect(boss["decision"]["who"]).to eq("Pell Vell, who burned with it")
    get location_path(dungeon)
    expect(response.body).to include("Its past", "Once the Vell manor, built 90 years ago.", "It burned 38 years ago, and was sealed after the fire.")

    town = campaign.locations.find { |l| l.map_node.world_place == varn }
    get location_path(town)
    expect(response.body).to include("Its past", "Founded #{varn.reload.past['founded']} years ago by #{varn.past['founder']}.")

    # Written in again, the GM's abbey stays as they wrote it.
    post world_history_path(world)
    expect(abbey.reload.past).to include("family" => "Vell", "edited" => true)
  end

  it "gives a place the history never saw a small past of its own, and the shop's made things a maker" do
    campaign = world.campaigns.create!(name: "Loose", gm: @admin)
    town = campaign.locations.create!(location_template: village, seed: 11)
    expect(town.past).to be_present
    expect(town.view["past"]).to include("founder", "founded")
    expect(Location.find(town.id).view["past"]).to eq(town.view["past"]) # from the seed, never stored

    blades = world.items.where.not(category: "consumable").limit(3).pluck(:slug)
    town.set_stock!(blades)
    town.update!(overrides: town.overrides.merge("stock" => blades))
    stories = town.reload.view["stock_stories"]
    expect(stories.keys - blades).to be_empty
    expect(stories.values.flat_map(&:values).join).to match(/#{town.view['past']['family']}|#{town.view['past']['rival']}|, smith|, jeweller|, weaver|, mason/)
  end

  it "keeps the history to the world's editors and GMs" do
    sign_in_as(make_user("Player"))
    get world_history_path(world)
    expect(response).to redirect_to(root_path)
    post world_history_path(world)
    expect(world.codex_entries.where.not(history_key: nil)).to be_empty
  end
end
