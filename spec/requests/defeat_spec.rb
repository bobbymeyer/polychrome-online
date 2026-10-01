# frozen_string_literal: true

require "rails_helper"

# After a wipe, the table decides what the story does with the party, and the GM settles it.
RSpec.describe "Defeat", type: :request do
  let(:campaign) { create_campaign.tap { |c| c.update!(gm: @admin, gil: 301) } }
  let!(:bartz) { create_character(campaign, name: "Bartz") }
  let!(:faris) { create_character(campaign, name: "Faris") }
  let(:tule) { campaign.map_nodes.create!(name: "Tule", kind: "town", x: 0, y: 0, visible: true) }
  let(:far_town) { campaign.map_nodes.create!(name: "Walse", kind: "town", x: 900, y: 0, visible: true) }
  let(:ruins) { campaign.map_nodes.create!(name: "Ruins", kind: "dungeon", x: 300, y: 0, visible: true) }

  before do
    far_town
    campaign.map_edges.create!(from_node: tule, to_node: ruins)
    campaign.update!(current_node: ruins)
    [ bartz, faris ].each { |c| c.update!(hp: 0) }
  end

  it "puts what happens now to the table when a battle is lost, as a choice the GM settles" do
    battle = start_battle(campaign: campaign)
    battle.apply!({ "type" => "gm_override", "op" => "end_battle", "result" => "defeat" }, actor: "gm")
    ask = campaign.reload.open_choice
    expect(ask).to be_what_now
    expect(ask.options).to eq([ "Retreat to Tule", "Everyone gets up", "Game over" ])
    expect(ask.body).to eq("Everyone is KO'd. What happens now? Retreat to Tule, Everyone gets up, or Game over.")
    expect(campaign.ask_what_now!).to eq(ask) # once
    get battle_panel_path(battle)
    expect(response.body).to include("Back to the table") # where what happens now is decided
    expect(response.body).not_to include("Another battle")

    get campaign_table_path(campaign)
    expect(response.body).to include("Retreat to Tule", "Settle on this")
    expect { ask.settle!("Everyone gets up") }
      .to have_broadcasted_to(stream(battle)).with(a_string_including("Somehow, one by one, everyone gets back up."))
    expect([ bartz.reload.hp, faris.reload.hp ]).to eq([ 1, 1 ])
    get battle_panel_path(battle)
    expect(response.body).to include("Somehow, one by one, everyone gets back up.")
  end

  it "lets the GM put it to the table when the party fell some other way" do
    get campaign_table_path(campaign)
    expect(response.body).to include("Everyone is KO'd. What happens now?", "Put it to the table")
    post campaign_recovery_path(campaign)
    expect(campaign.open_choice).to be_what_now
    sign_in_as(make_user("Kim"))
    post campaign_recovery_path(campaign)
    expect(response).to have_http_status(:forbidden).or redirect_to(root_path)
  end

  it "comes before a choice already open, which is the table's again after, and nobody goes anywhere meanwhile" do
    scene_choice = Message.choice(campaign, options: [ "Board the train", "Run" ]).tap(&:save!)
    expect(campaign.ways_on).to be_empty
    expect { campaign.take_way!("To Tule") }.to raise_error(Refusal)

    ask = campaign.ask_what_now!
    expect(ask).to be_what_now
    expect(campaign.open_choice).to eq(ask)
    ask.settle!("Everyone gets up")
    expect(campaign.reload.open_choice).to eq(scene_choice)
    expect(campaign.ways_on).to be_present
  end

  it "retreats to the nearest town by road, rested and half as rich" do
    campaign.ask_what_now!.settle!("Retreat to Tule")
    campaign.reload
    expect(campaign.current_node).to eq(tule)
    expect(campaign.gil).to eq(151)
    expect([ bartz.reload, faris.reload ]).to all(be_conscious)
    expect(bartz.current_hp).to eq(bartz.stats["max_hp"])
    expect(campaign.messages.pluck(:body)).to include("The party comes to in Tule, bruised but alive, 150 gil lighter.")
  end

  it "gets everyone up where they fell, with 1 HP" do
    campaign.ask_what_now!.settle!("Everyone gets up")
    expect([ bartz.reload.hp, faris.reload.hp ]).to eq([ 1, 1 ])
    expect(campaign.reload.current_node).to eq(ruins)
    get campaign_table_path(campaign)
    expect(response.body).to include(%(<strong class="is-low" data-change="number">1</strong>)) # amber at the table, as in battle
  end

  it "can end the story, and only when everyone is down" do
    ask = campaign.ask_what_now!
    ask.settle!("Game over")
    expect(campaign.messages.pluck(:body)).to include("The party has fallen. Their story ends here.")
    expect(bartz.reload).not_to be_conscious

    bartz.update!(hp: 5)
    expect(campaign.ask_what_now!).to be_nil
    expect { campaign.recover!("get_up") }.to raise_error(Refusal, "Someone is still standing")
  end

  it "retreats by open roads only: never over a blocked pass" do
    over_the_pass = campaign.map_nodes.create!(name: "Pass Town", kind: "town", x: 400, y: 0, visible: true)
    campaign.map_edges.create!(from_node: ruins, to_node: over_the_pass, state: "blocked")
    expect(campaign.refuge).to eq(tule)
  end
end
