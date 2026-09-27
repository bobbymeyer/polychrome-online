# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/base_world")
require "turbo/broadcastable/test_helper"

# What a player runs into, from signing in to the end of a battle.
RSpec.describe "The player's way through", type: :request do
  include Turbo::Broadcastable::TestHelper

  let!(:world) { Seeds::BaseWorld.run }
  let(:campaign) { world.campaigns.create!(name: "Crystal Road", gm: @admin) }
  let(:knight) { world.jobs.find_by!(slug: "knight") }
  let(:white_mage) { world.jobs.find_by!(slug: "white_mage") }
  let!(:krile) { make_user("Krile") }

  def battle_with(*characters) = BattleRecord.start!(campaign: campaign, characters: characters, name: "Road", encounter: { "goblin" => 1 }, seed: 3)

  it "offers the admin a new campaign from the home page" do
    get root_path
    expect(response.body).to include("New campaign", "you run it as its GM")
  end

  it "lists your campaigns on the home page, then the ones to join" do
    campaign.characters.create!(name: "Krile", job: white_mage, user: krile)
    world.campaigns.create!(name: "Someone else's")
    sign_in_as(krile)
    get root_path
    mine, others = response.body.split("<h2>Other campaigns</h2>")
    expect(mine).to include("Your campaigns", "Crystal Road", "You play Krile", "Table →")
    expect(others).to include("Someone else&#39;s")
  end

  it "starts a player's new character knowing their job's first ability" do
    sign_in_as(krile)
    post campaign_characters_path(campaign), params: { character: { name: "Krile", job_id: white_mage.id } }
    character = campaign.characters.find_by!(name: "Krile")
    expect(character.character_job.level).to eq(2) # two job levels per level
    expect(character.battle_abilities.map(&:slug)).to include("cure")
  end

  it "seats you as your only character, or as the GM of your campaign, without asking; standing up sticks" do
    mine = campaign.characters.create!(name: "Krile", job: white_mage, user: krile)
    campaign.characters.create!(name: "Bartz", job: knight)

    sign_in_as(krile)
    get campaign_table_path(campaign)
    expect(response.body).to include("At the table as <strong>Krile</strong>")
    delete campaign_table_seat_path(campaign)
    get campaign_table_path(campaign)
    expect(response.body).to include("Take a seat")

    battle = battle_with(mine, campaign.characters.find_by!(name: "Bartz"))
    get battle_panel_path(battle)
    expect(response.body).to include("Take a seat") # stood up at the table, so not seated here either

    sign_in_as(@admin) # the GM, who plays nobody
    get campaign_table_path(campaign)
    expect(response.body).to include("At the table as <strong>GM</strong>")
  end

  it "leaves the GM's characters unclaimed, and seats the GM as GM even if they own one" do
    post campaign_characters_path(campaign), params: { character: { name: "Bartz", job_id: knight.id } }
    expect(campaign.characters.find_by!(name: "Bartz").user).to be_nil

    campaign.characters.create!(name: "Faris", job: knight, user: @admin) # made before this fix
    get campaign_table_path(campaign)
    expect(response.body).to include("At the table as <strong>GM</strong>")
  end

  it "takes a character back off auto when their player sits down and chooses" do
    lenna = campaign.characters.create!(name: "Lenna", job: white_mage, user: krile)
    bartz = campaign.characters.create!(name: "Bartz", job: knight)
    battle = battle_with(lenna, bartz)
    expect(battle.auto?(bartz.battle_unit_id)).to be(true)

    patch battle_auto_path(battle), params: { unit: bartz.battle_unit_id, on: "0" } # the GM
    expect(battle.reload.auto?(bartz.battle_unit_id)).to be(false)
    patch battle_auto_path(battle), params: { unit: bartz.battle_unit_id, on: "1" }
    expect(battle.reload.auto?(bartz.battle_unit_id)).to be(true)

    bartz.update!(user: krile) # Krile picks Bartz up too
    sign_in_as(krile)
    post battle_seat_path(battle), params: { seat: bartz.battle_unit_id }
    post battle_actions_path(battle), params: { command: { kind: "ability", ability: "attack", target: "goblin" } }
    expect(battle.reload.auto?(bartz.battle_unit_id)).to be(false)

    # ...and can put themselves back on it, to talk and let the fight run.
    patch battle_auto_path(battle), params: { unit: bartz.battle_unit_id, on: "1" }
    expect(battle.reload.auto?(bartz.battle_unit_id)).to be(true)
  end

  it "shows a monster's weaknesses only once the party has found them, and remembers" do
    bartz = campaign.characters.create!(name: "Bartz", job: knight)
    battle = battle_with(bartz)
    help = -> { ApplicationController.helpers.target_help(battle.reload, battle.state, "goblin") }
    expect(help.()).to include("Weaknesses unknown").and(satisfy { |h| !h.include?("Weak to Fire") })

    campaign.learn_from!([ { "type" => "damage", "target" => "goblin", "damage_type" => "fire", "amount" => 9 } ], battle.state)
    # Seeing a typed hit land shows what the monster is, and the chart does the rest.
    expect(help.()).to include("Normal type", "Weak to Fire and Fighting", "Immune to Ghost")
    expect(campaign.reload.known_affinities).to eq("goblin" => { "types" => [ "normal" ], "fire" => "weak" })

    campaign.learn_from!([ { "type" => "scan", "target" => "goblin" } ], battle.state)
    expect(campaign.reload.known_affinities["goblin"]).to include("ice" => "none", "sleep" => "none")
  end

  it "puts stolen things in the bag however the battle ends" do
    bartz = campaign.characters.create!(name: "Bartz", job: knight)
    battle = battle_with(bartz)
    battle.update!(state: battle.state.merge("stolen" => [ "potion" ]))
    battle.apply!({ "type" => "gm_override", "op" => "end_battle", "result" => "fled" }, actor: "gm")
    expect(battle.reload.settlement["stolen"]).to eq([ "Potion" ])
    expect(campaign.quantity_of(world.items.find_by!(slug: "potion"))).to eq(1)
  end

  it "points the table at the newest battle, live, and stops once it's over or called off" do
    bartz = campaign.characters.create!(name: "Bartz", job: knight)
    old = battle_with(bartz)
    streams = capture_turbo_stream_broadcasts([ campaign, :table ]) { @new = battle_with(bartz) }
    header = streams.find { |s| s["target"] == "table_battle" }
    expect(header.to_html).to include("Road is on", "/battles/#{@new.id}")

    get campaign_table_path(campaign)
    expect(response.body[%r{<div id="table_battle">.*?</div>}m]).to include("/battles/#{@new.id}")
    expect(response.body.scan("Join the battle").size).to eq(1) # only the current battle's line invites you

    post call_off_battle_path(@new)
    expect(@new.reload.status).to eq("abandoned")
    get campaign_table_path(campaign)
    expect(response.body[%r{<div id="table_battle">.*?</div>}m]).to include("/battles/#{old.id}")
    post call_off_battle_path(old)
    get campaign_table_path(campaign)
    expect(response.body).not_to include("is on →")
  end

  it "calling off changes nothing: no settlement, HP and items as they were" do
    bartz = campaign.characters.create!(name: "Bartz", job: knight)
    bartz.update!(hp: 50)
    campaign.add_item!(world.items.find_by!(slug: "potion"), 2)
    battle = battle_with(bartz)
    post call_off_battle_path(battle)
    expect(battle.reload.settlement).to be_nil
    expect(bartz.reload.hp).to eq(50)
    expect(campaign.quantity_of(world.items.find_by!(slug: "potion"))).to eq(2)
    expect(campaign.messages.last.body).to eq("Road was called off.")
    expect(campaign.reload).not_to be_battle_on

    get campaign_path(campaign)
    expect(response.body).to include("Called off")
  end

  it "only lets the GM call a battle off" do
    battle = battle_with(campaign.characters.create!(name: "Krile", job: white_mage, user: krile))
    sign_in_as(krile)
    post call_off_battle_path(battle)
    expect(battle.reload.status).to eq("input")
  end

  it "shows players the result, not the GM's tools or the replay seed" do
    mine = campaign.characters.create!(name: "Krile", job: white_mage, user: krile)
    battle = battle_with(mine)
    post battle_actions_path(battle), params: { gm: { op: "end_battle", result: "victory" } } # as the admin GM
    get battle_panel_path(battle)
    expect(response.body).to include("Another battle", "replays exactly")

    sign_in_as(krile)
    get battle_panel_path(battle)
    expect(response.body).to include("Victory!", "Back to the table")
    expect(response.body).not_to include("Another battle", "replays exactly")
  end

  it "says who plays each character on the campaign page" do
    campaign.characters.create!(name: "Krile", job: white_mage, user: krile)
    campaign.characters.create!(name: "Bartz", job: knight)
    campaign.characters.create!(name: "Faris", job: knight, user: make_user("Faris's player"))
    sign_in_as(krile)
    get campaign_path(campaign)
    expect(response.body).to include("<strong>You</strong>", "Unclaimed: sit as them at the table", "Played by Faris&#39;s player")
  end
end
