# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/base_world")

RSpec.describe "Items and shops", type: :request do
  let!(:world) { Seeds::BaseWorld.run }
  let(:campaign) { world.campaigns.create!(name: "Crystal Road", gm: @admin, gil: 200) }
  let(:potion) { world.items.find_by!(slug: "potion") }
  let(:antidote) { world.items.find_by!(slug: "antidote") }

  describe "in battle" do
    let!(:bartz) { campaign.characters.create!(name: "Bartz", job: world.jobs.find_by!(slug: "knight"), starting_level: 5) }
    let!(:faris) { campaign.characters.create!(name: "Faris", job: world.jobs.find_by!(slug: "monk"), starting_level: 5) }

    before do
      campaign.add_item!(potion, 2)
      campaign.add_item!(world.items.find_by!(slug: "broadsword")) # gear never comes into battle
    end

    it "brings the bag's usable items, offers them as a command, and takes used ones out of the bag after" do
      battle = BattleRecord.start!(campaign: campaign, characters: [ bartz, faris ], name: "Road", encounter: { "goblin" => 1 }, seed: 3)
      expect(battle.state["items"].keys).to eq([ "potion" ])

      post battle_seat_path(battle), params: { seat: bartz.battle_unit_id }
      get battle_panel_path(battle)
      expect(response.body).to include(">\n        Item <span class=\"menu__cost\">×2</span>")
      get battle_panel_path(battle, items: 1)
      expect(response.body).to include("Potion", "Single ally · Restore HP, power 30 · 2 left")
      get battle_panel_path(battle, item: "potion")
      expect(response.body).to include("<strong>Potion</strong>: choose a target.")

      post battle_actions_path(battle), params: { command: { kind: "item", item: "potion", target: faris.battle_unit_id } }
      expect(battle.reload.state["inputs"][bartz.battle_unit_id]).to include("kind" => "item", "item" => "potion")
      get battle_panel_path(battle)
      expect(response.body).to include("Ready: <strong>Potion</strong>")

      post battle_seat_path(battle), params: { seat: "gm" }
      post battle_actions_path(battle), params: { gm: { op: "execute_round" } }
      expect(battle.reload.state["items"]["potion"]["count"]).to eq(1)
      expect(battle.battle_events.map(&:payload)).to include(a_hash_including("type" => "item_used", "item" => "potion"))

      post battle_actions_path(battle), params: { gm: { op: "end_battle", result: "fled" } }
      expect(campaign.reload.quantity_of(potion)).to eq(1)
      expect(battle.reload.settlement["used"]).to eq("Potion" => 1)
      expect(campaign.messages.last.body).to include("Used 1 × Potion.")
    end

    it "leaves the Item command out when the party carries nothing usable" do
      campaign.use_items!(potion, 2)
      battle = BattleRecord.start!(campaign: campaign, characters: [ bartz, faris ], name: "Road", encounter: { "goblin" => 1 }, seed: 3)
      post battle_seat_path(battle), params: { seat: bartz.battle_unit_id }
      get battle_panel_path(battle)
      expect(response.body).not_to include("data-menu-key=\"Item\"")
    end
  end

  describe "shops" do
    let(:node) { campaign.map_nodes.create!(name: "Port", kind: "town", x: 100, y: 100, visible: true) }
    let(:town) do
      post campaign_table_seat_path(campaign), params: { seat: "gm" }
      post map_node_location_path(node), params: { location_template_id: world.location_templates.find_by!(slug: "port_town").id }
      node.reload.location.tap { |l| l.set_stock!(%w[potion antidote]) }
    end
    let!(:lenna) { make_user("Lenna") }

    before do
      campaign.characters.create!(name: "Lenna", job: world.jobs.find_by!(slug: "white_mage"), user: lenna)
      campaign.update!(current_node: node)
      town
      sign_in_as(lenna)
    end

    it "sells the stock for party gil, and buys from the bag at half price" do
      get location_path(town)
      expect(response.body).to include("The party has <strong>200 gil</strong>", "Antidote", 'value="Buy"')

      post buy_location_shop_path(town), params: { item: "potion", quantity: 3 }
      expect(campaign.reload.gil).to eq(80)
      expect(campaign.quantity_of(potion)).to eq(3)
      expect(campaign.messages.last.body).to eq("Lenna bought 3 × Potion in #{town.name} for 120 gil.")

      post sell_location_shop_path(town), params: { item: "potion", quantity: 2 }
      expect(campaign.reload.gil).to eq(120)
      expect(campaign.quantity_of(potion)).to eq(1)
    end

    it "won't sell what it doesn't stock, overspend, or buy what the bag lacks" do
      post buy_location_shop_path(town), params: { item: "phoenix_down" }
      expect(flash[:alert]).to include("doesn't sell Phoenix Down")
      post buy_location_shop_path(town), params: { item: "antidote", quantity: 5 }
      expect(flash[:alert]).to include("The party has 200 gil; 5 × Antidote costs 250")
      post sell_location_shop_path(town), params: { item: "antidote" }
      expect(flash[:alert]).to include("The bag has 0 × Antidote")
      expect(campaign.reload.gil).to eq(200)
    end

    it "only opens where the party is, unless you're the GM" do
      campaign.update!(current_node: campaign.map_nodes.create!(name: "Elsewhere", kind: "field", x: 300, y: 300, visible: true))
      get location_path(town)
      expect(response.body).to include("The party has to be here to shop.")
      expect(response.body).not_to include('value="Buy"')
      post buy_location_shop_path(town), params: { item: "potion" }
      expect(flash[:alert]).to eq("You can only shop in the town where the party is.")

      sign_in_as(@admin)
      post buy_location_shop_path(town), params: { item: "potion" }
      expect(campaign.reload.quantity_of(potion)).to eq(1)
    end
  end
end
