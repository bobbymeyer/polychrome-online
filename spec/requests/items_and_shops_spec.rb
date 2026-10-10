# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Items and shops", type: :request do
  let!(:world) { base_world }
  let(:campaign) { base_campaign(gm: @admin, gil: 200) }
  let(:potion) { world.items.find_by!(slug: "potion") }
  let(:antidote) { world.items.find_by!(slug: "antidote") }

  describe "in battle" do
    let!(:bartz) { base_character(campaign, name: "Bartz", starting_level: 5, starting_gear: false) }
    let!(:faris) { base_character(campaign, name: "Faris", job: "monk", starting_level: 5, starting_gear: false) }

    before do
      bartz.add_item!(potion, 1)
      faris.add_item!(potion, 1) # what each carries goes in together
      bartz.add_item!(world.items.find_by!(slug: "broadsword")) # gear never comes into battle
      campaign.add_item!(potion, 5) # the chest comes too, flattened in with the bags
    end

    it "brings everything the party has, bags and chest as one count, offers it as a command, and takes used ones out of their bags first" do
      battle = BattleRecord.start!(campaign: campaign, characters: [ bartz, faris ], name: "Road", encounter: { "goblin" => 3 }, seed: 3)
      expect(battle.state["items"].keys).to eq([ "potion" ])

      sit_in_battle(battle, bartz.battle_unit_id)
      get battle_panel_path(battle)
      expect(page.css("a").map(&:text)).to include("Item")
      expect(page.css("td.pick-row__cost").map(&:text)).to include("×7")
      expect(page.at("[data-menu-key=Talk]")).to be_present # talk is an action here
      get battle_panel_path(battle, items: 1)
      expect(response.body).to include("Potion", "Single ally · Restore HP, power 30 · 7 left")
      get battle_panel_path(battle, item: "potion")
      expect(page.text).to include("Potion: choose a target.")
      expect(page.css("strong").map(&:text)).to include("Potion")

      post battle_actions_path(battle), params: { command: { kind: "item", item: "potion", target: faris.battle_unit_id } }
      expect(battle.reload.state["inputs"][bartz.battle_unit_id]).to include("kind" => "item", "item" => "potion")
      get battle_panel_path(battle)
      expect(page.text).to include("Ready: Potion")

      sit_in_battle(battle, "gm")
      post battle_actions_path(battle), params: { gm: { op: "execute_round" } }
      expect(battle.reload.state["items"]["potion"]["count"]).to eq(6)
      expect(battle.battle_events.map(&:payload)).to include(a_hash_including("type" => "item_used", "item" => "potion"))

      post battle_actions_path(battle), params: { gm: { op: "end_battle", result: "fled" } }
      expect([ bartz.reload.quantity_of(potion), faris.reload.quantity_of(potion), campaign.reload.quantity_of(potion) ]).to eq([ 0, 1, 5 ])
      expect(battle.reload.settlement["used"]).to eq("Potion" => 1)
      expect(campaign.messages.last.body).to include("Used 1 × Potion.")
    end

    it "counts what a thief got away with as lost, not used, and out of the bags all the same" do
      battle = BattleRecord.start!(campaign: campaign, characters: [ bartz, faris ], name: "Road", encounter: { "goblin" => 1 }, seed: 3)
      # A goblin with light fingers took one (Battle::Effects#lift), and the party runs.
      state = battle.state.deep_dup
      state["items"]["potion"]["count"] -= 1
      state["units"].find { |u| u["side"] == "enemy" }["pilfered"] = %w[potion]
      battle.update!(state: state)

      sit_in_battle(battle, "gm")
      post battle_actions_path(battle), params: { gm: { op: "end_battle", result: "fled" } }
      expect(battle.reload.settlement).to include("lost" => { "Potion" => 1 })
      expect(battle.settlement["used"]).to be_blank
      expect(bartz.reload.quantity_of(potion) + faris.reload.quantity_of(potion) + campaign.reload.quantity_of(potion)).to eq(6)
      expect(campaign.messages.last.body).to include("Lost 1 × Potion to thieves.")
    end

    it "leaves the Item command out when the party has nothing usable" do
      campaign.use_items!(potion, 7) # their bags first, then the chest
      battle = BattleRecord.start!(campaign: campaign, characters: [ bartz, faris ], name: "Road", encounter: { "goblin" => 1 }, seed: 3)
      sit_in_battle(battle, bartz.battle_unit_id)
      get battle_panel_path(battle)
      expect(page.at("[data-menu-key=Item]")).to be_nil
    end
  end

  describe "shops" do
    let(:node) { campaign.map_nodes.create!(name: "Port", kind: "town", x: 100, y: 100, visible: true) }
    let(:town) do
      sit(campaign, "gm")
      post map_node_location_path(node), params: { location_template_id: world.location_templates.find_by!(slug: "port_town").id }
      node.reload.location.tap { |l| l.set_stock!(%w[potion antidote]) }
    end
    let!(:lenna) { make_user("Lenna") }

    before do
      base_character(campaign, name: "Lenna", job: "white_mage", user: lenna, starting_gear: false)
      campaign.update!(current_node: node)
      town
      sign_in_as(lenna)
    end

    it "sells the stock for party gil into the buyer's bag, and buys from a bag or the chest at half price" do
      character = campaign.characters.find_by!(name: "Lenna")
      campaign.add_item!(potion) # one in the chest
      get location_path(town)
      expect(page.text).to include("The party has 200 gil", "Antidote")
      expect(page.at("input[value=Buy]")).to be_present

      post location_purchases_path(town), params: { item: "potion", quantity: 3 }
      expect(campaign.reload.gil).to eq(80)
      expect(character.quantity_of(potion)).to eq(3)
      expect(campaign.quantity_of(potion)).to eq(1)
      expect(campaign.messages.last.body).to eq("Lenna bought 3 × Potion in #{town.name} for 120 gil.")

      get location_path(town)
      expect(response.body).to include("×3, Lenna&#39;s bag", "×1, the chest")
      post location_sales_path(town), params: { item: "potion", quantity: 2, character_id: character.id }
      expect(campaign.reload.gil).to eq(120)
      expect(character.quantity_of(potion)).to eq(1)
      post location_sales_path(town), params: { item: "potion", quantity: 1 }
      expect(campaign.reload.gil).to eq(140)
      expect(campaign.quantity_of(potion)).to eq(0)
    end

    it "won't sell what it doesn't stock, overspend, or buy what the chest lacks" do
      post location_purchases_path(town), params: { item: "phoenix_down" }
      expect(flash[:alert]).to include("doesn't sell Phoenix Down")
      post location_purchases_path(town), params: { item: "antidote", quantity: 5 }
      expect(flash[:alert]).to include("The party has 200 gil; 5 × Antidote costs 250")
      post location_sales_path(town), params: { item: "antidote" }
      expect(flash[:alert]).to include("The chest has 0 × Antidote")
      expect(campaign.reload.gil).to eq(200)
    end

    it "puts each service under its building, saying what it's for; the party does it at the table like any other thing to do" do
      lenna_character = campaign.characters.find_by!(name: "Lenna")
      lenna_character.update!(hp: 10, mp: 0)
      inn = town.view["services"].find { |sv| sv["kind"] == "inn" }
      price = town.service_price("inn", lenna_character)
      label = "Rooms at #{inn['name']} (#{price} gil, overnight)"
      get location_path(town)
      expect(page.at("#service-inn")).to be_present
      expect(page.at("#service-shop")).to be_present
      expect(page.at(".pick-row.service.service--inn")).to be_present
      expect(response.body).to include("Done at the table, under Do")
      expect(response.body).not_to include("suggest", "Rooms at", campaign_ways_path(campaign)) # one home for doing it: the table
      # What each is for, and what it costs, before it's opened.
      offers = page.css("td.pick-row__cost.service__offer").map(&:text)
      expect(offers).to include(match(/\ARest the night · \d+ gil\z/), "Buy and sell")

      post campaign_ways_path(campaign), params: { way: label }
      expect(response).to have_http_status(:forbidden) # not while the table is talking
      expect(campaign.open_choice).to be_nil

      campaign.call_controls!("doing")
      get location_path(town)
      expect(response.body).not_to include("suggest", campaign_ways_path(campaign)) # still not here, called or not
      get campaign_table_path(campaign)
      expect(page.at("#table_ways").text).to include("Rooms at #{inn['name']}", "suggest") # here
      post campaign_ways_path(campaign), params: { way: label }
      expect(campaign.open_choice.tally[label]).to eq([ "Lenna" ])

      sign_out
      sign_in_as(@admin)
      sit(campaign, "gm")
      post campaign_ways_path(campaign), params: { way: label, go: 1 }
      expect(campaign.reload.gil).to eq(200 - price)
      expect(lenna_character.reload.current_hp).to eq(lenna_character.stats["max_hp"])
      expect(campaign.messages.pluck(:body)).to include("Port: Rooms at #{inn['name']} (#{price} gil).")
    end

    it "only opens where the party is, unless you're the GM" do
      campaign.update!(current_node: campaign.map_nodes.create!(name: "Elsewhere", kind: "field", x: 300, y: 300, visible: true))
      get location_path(town)
      expect(response.body).to include("The party has to be here to use them.")
      expect(page.at("input[value=Buy]")).to be_nil
      post location_purchases_path(town), params: { item: "potion" }
      expect(flash[:alert]).to eq("You can only shop in the town where the party is.")

      sign_in_as(@admin)
      post location_purchases_path(town), params: { item: "potion" }
      expect(campaign.reload.quantity_of(potion)).to eq(1)
    end
  end

  describe "outside battle" do
    let!(:bartz) { base_character(campaign, name: "Bartz", starting_level: 5, starting_gear: false) }
    let!(:lenna) { base_character(campaign, name: "Lenna", job: "white_mage", starting_level: 5, starting_gear: false) }

    before do
      lenna.add_item!(potion, 2)
      lenna.add_item!(antidote)
      bartz.update!(hp: 20)
    end

    it "uses a healing item from their own bag on a party member, through the engine's formula" do
      get character_path(lenna)
      expect(page.at("#items")).to be_present
      expect(page.at("[data-key=gear]")).to be_present
      expect(response.body).to include("Potion", "Bartz (HP 20/")
      usable = page.at("#items").text
      expect(usable).not_to include("Antidote") # cures only work in battle (it's in the bag, above)
      expect(usable).not_to include("Lenna (HP") # unhurt: nothing to heal

      bartz.update!(hp: bartz.stats["max_hp"])
      get character_path(lenna)
      expect(response.body).to include("Nobody is hurt")
      bartz.update!(hp: 20)

      rng = campaign.rng
      post character_item_use_path(lenna), params: { item: "potion", target_id: bartz.id }
      expect(bartz.reload.hp).to be > 20
      expect(lenna.reload.quantity_of(potion)).to eq(1)
      expect(campaign.reload.rng).not_to eq(rng)
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
      expect(lenna.reload.quantity_of(potion)).to eq(2)
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
      sit(campaign, "gm")
      post map_node_location_path(node), params: { location_template_id: world.location_templates.find_by!(slug: "port_town").id }
      node.reload.location
    end
    let(:broadsword) { world.items.find_by!(slug: "broadsword") }
    let!(:bartz) { base_character(campaign, name: "Bartz", starting_gear: false) }

    before do
      campaign.update!(current_node: node)
      bartz.add_item!(broadsword)
      bartz.equip!(broadsword)
    end

    it "takes it off and sells it for half" do
      get location_path(town)
      expect(response.body).to include("Sell what the party is wearing", "Broadsword")

      post location_sales_path(town), params: { character_id: bartz.id, slot: "weapon" }
      expect(bartz.reload.equipped["weapon"]).to be_nil
      expect(campaign.reload.gil).to eq(200 + broadsword.resale_price)
      expect(bartz.quantity_of(broadsword)).to eq(0)
    end

    it "only for the character's player or the GM" do
      town
      bartz.update!(user: make_user("Someone"))
      lenna = make_user("Lenna")
      base_character(campaign, name: "Lenna", job: "white_mage", user: lenna, starting_gear: false)
      sign_in_as(lenna)
      get location_path(town)
      expect(response.body).not_to include("Sell what the party is wearing")
      post location_sales_path(town), params: { character_id: bartz.id, slot: "weapon" }
      expect(bartz.reload.equipped["weapon"]).to be_present
    end
  end
end
