# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Items and shops", type: :request do
  let!(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "Crystal Road", gm: @admin, gil: 200) }
  let(:potion) { world.items.find_by!(slug: "potion") }
  let(:antidote) { world.items.find_by!(slug: "antidote") }

  describe "in battle" do
    let!(:bartz) { campaign.characters.create!(name: "Bartz", job: world.jobs.find_by!(slug: "knight"), starting_level: 5, starting_gear: false) }
    let!(:faris) { campaign.characters.create!(name: "Faris", job: world.jobs.find_by!(slug: "monk"), starting_level: 5, starting_gear: false) }

    before do
      campaign.add_item!(potion, 2)
      campaign.add_item!(world.items.find_by!(slug: "broadsword")) # gear never comes into battle
    end

    it "brings the bag's usable items, offers them as a command, and takes used ones out of the bag after" do
      battle = BattleRecord.start!(campaign: campaign, characters: [ bartz, faris ], name: "Road", encounter: { "goblin" => 3 }, seed: 3)
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
      campaign.characters.create!(name: "Lenna", job: world.jobs.find_by!(slug: "white_mage"), user: lenna, starting_gear: false)
      campaign.update!(current_node: node)
      town
      sign_in_as(lenna)
    end

    it "sells the stock for party gil, and buys from the bag at half price" do
      get location_path(town)
      expect(response.body).to include("The party has <strong>200 gil</strong>", "Antidote", 'value="Buy"')

      post location_purchases_path(town), params: { item: "potion", quantity: 3 }
      expect(campaign.reload.gil).to eq(80)
      expect(campaign.quantity_of(potion)).to eq(3)
      expect(campaign.messages.last.body).to eq("Lenna bought 3 × Potion in #{town.name} for 120 gil.")

      post location_sales_path(town), params: { item: "potion", quantity: 2 }
      expect(campaign.reload.gil).to eq(120)
      expect(campaign.quantity_of(potion)).to eq(1)
    end

    it "won't sell what it doesn't stock, overspend, or buy what the bag lacks" do
      post location_purchases_path(town), params: { item: "phoenix_down" }
      expect(flash[:alert]).to include("doesn't sell Phoenix Down")
      post location_purchases_path(town), params: { item: "antidote", quantity: 5 }
      expect(flash[:alert]).to include("The party has 200 gil; 5 × Antidote costs 250")
      post location_sales_path(town), params: { item: "antidote" }
      expect(flash[:alert]).to include("The bag has 0 × Antidote")
      expect(campaign.reload.gil).to eq(200)
    end

    it "puts each service under its building, and lets a character pay for a night at the inn" do
      lenna_character = campaign.characters.find_by!(name: "Lenna")
      lenna_character.update!(hp: 10, mp: 0)
      get location_path(town)
      expect(response.body).to include('id="service-inn"', 'id="service-shop"', 'class="service service--inn"', ">Rest<")

      post location_services_path(town), params: { kind: "inn", character_id: lenna_character.id }
      expect(response).to redirect_to(location_path(town, anchor: "service-inn"))
      price = campaign.service_price("inn", lenna_character)
      expect(campaign.reload.gil).to eq(200 - price)
      expect(lenna_character.reload.current_hp).to eq(lenna_character.stats["max_hp"])
      expect(campaign.messages.last.body).to include("Lenna takes a room", "#{price} gil")
      expect(flash[:notice]).to eq(campaign.messages.last.body) # said where you are, not only in the log

      post location_services_path(town), params: { kind: "inn", character_id: lenna_character.id }
      expect(flash[:alert]).to include("already rested")

      other = campaign.characters.create!(name: "Faris", job: world.jobs.find_by!(slug: "knight"), user: make_user("Faris"), starting_gear: false)
      other.update!(hp: 1)
      post location_services_path(town), params: { kind: "inn", character_id: other.id }
      expect(flash[:alert]).to include("isn't yours to pay for")
    end

    it "only opens where the party is, unless you're the GM" do
      campaign.update!(current_node: campaign.map_nodes.create!(name: "Elsewhere", kind: "field", x: 300, y: 300, visible: true))
      get location_path(town)
      expect(response.body).to include("The party has to be here to use them.")
      expect(response.body).not_to include('value="Buy"')
      post location_purchases_path(town), params: { item: "potion" }
      expect(flash[:alert]).to eq("You can only shop in the town where the party is.")

      sign_in_as(@admin)
      post location_purchases_path(town), params: { item: "potion" }
      expect(campaign.reload.quantity_of(potion)).to eq(1)
    end
  end

  describe "outside battle" do
    let!(:bartz) { campaign.characters.create!(name: "Bartz", job: world.jobs.find_by!(slug: "knight"), starting_level: 5, starting_gear: false) }
    let!(:lenna) { campaign.characters.create!(name: "Lenna", job: world.jobs.find_by!(slug: "white_mage"), starting_level: 5, starting_gear: false) }

    before do
      campaign.add_item!(potion, 2)
      campaign.add_item!(antidote)
      bartz.update!(hp: 20)
    end

    it "uses a healing item from the bag on a party member, through the engine's formula" do
      get character_path(lenna)
      expect(response.body).to include('id="items"', "Potion", "Bartz (HP 20/")
      expect(response.body).not_to include("Antidote <span") # cures only work in battle

      rng = campaign.rng
      post character_item_use_path(lenna), params: { item: "potion", target_id: bartz.id }
      expect(bartz.reload.hp).to be > 20
      expect(campaign.reload.quantity_of(potion)).to eq(1)
      expect(campaign.rng).not_to eq(rng)
      expect(campaign.messages.last.body).to eq("Lenna uses Potion on Bartz: HP 20 → #{bartz.hp}.")
    end

    it "refuses what would do nothing, and anything while a battle is on" do
      post character_item_use_path(lenna), params: { item: "potion", target_id: lenna.id }
      expect(flash[:alert]).to eq("Lenna is already at full HP")
      post character_item_use_path(lenna), params: { item: "antidote", target_id: bartz.id }
      expect(flash[:alert]).to eq("Antidote can only be used in battle")

      BattleRecord.start!(campaign: campaign, characters: [ bartz, lenna ], name: "Road", encounter: { "goblin" => 1 }, seed: 3)
      post character_item_use_path(lenna), params: { item: "potion", target_id: bartz.id }
      expect(flash[:alert]).to include("Not while a battle is on")
      expect(campaign.reload.quantity_of(potion)).to eq(2)
    end

    it "is only for someone who plays that character (or the GM)" do
      bartz.update!(user: make_user("Someone"))
      sign_in_as(make_user("Stranger"))
      post character_item_use_path(bartz), params: { item: "potion" }
      expect(bartz.reload.hp).to eq(20)
    end
  end

  describe "selling worn gear" do
    let(:node) { campaign.map_nodes.create!(name: "Port", kind: "town", x: 100, y: 100, visible: true) }
    let(:town) do
      post campaign_table_seat_path(campaign), params: { seat: "gm" }
      post map_node_location_path(node), params: { location_template_id: world.location_templates.find_by!(slug: "port_town").id }
      node.reload.location
    end
    let(:broadsword) { world.items.find_by!(slug: "broadsword") }
    let!(:bartz) { campaign.characters.create!(name: "Bartz", job: world.jobs.find_by!(slug: "knight"), starting_gear: false) }

    before do
      campaign.update!(current_node: node)
      campaign.add_item!(broadsword)
      bartz.equip!(broadsword)
    end

    it "takes it off and sells it for half" do
      get location_path(town)
      expect(response.body).to include("Sell what the party is wearing", "Broadsword")

      post location_sales_path(town), params: { character_id: bartz.id, slot: "weapon" }
      expect(bartz.reload.equipped["weapon"]).to be_nil
      expect(campaign.reload.gil).to eq(200 + broadsword.resale_price)
      expect(campaign.quantity_of(broadsword)).to eq(0)
    end

    it "only for the character's player or the GM" do
      town
      bartz.update!(user: make_user("Someone"))
      lenna = make_user("Lenna")
      campaign.characters.create!(name: "Lenna", job: world.jobs.find_by!(slug: "white_mage"), user: lenna, starting_gear: false)
      sign_in_as(lenna)
      get location_path(town)
      expect(response.body).not_to include("Sell what the party is wearing")
      post location_sales_path(town), params: { character_id: bartz.id, slot: "weapon" }
      expect(bartz.reload.equipped["weapon"]).to be_present
    end
  end
end
