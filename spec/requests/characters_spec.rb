# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Campaigns and characters", type: :request do
  let!(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "Crystal Road") }
  let(:knight) { world.jobs.find_by!(slug: "knight") }
  let(:bartz) { campaign.characters.create!(name: "Bartz", player_name: "Sam", job: knight, starting_level: 5, starting_job_level: 1, starting_gear: false) }
  let(:item) { ->(slug) { world.items.find_by!(slug: slug) } }

  describe "campaigns" do
    it "are created from a world and list their party, bag and battles" do
      post world_campaigns_path(world), params: { campaign: { name: "Second Run" } }
      campaign = Campaign.find_by!(name: "Second Run")
      expect(response).to redirect_to(campaign_path(campaign))

      campaign.characters.create!(name: "Lenna", job: world.jobs.find_by!(slug: "white_mage"))
      campaign.add_item!(item.("potion"), 3)
      get campaign_path(campaign)
      expect(response.body).to include("Lenna", "White Mage", "Potion", "New battle")

      get world_path(world)
      expect(response.body).to include("Second Run")
    end

    it "carries each character's reason for being here: on their card and sheet, and into battle as their cry" do
      post campaign_characters_path(campaign), params: { character: { name: "Faris", motive: "My sister is out there.", job_id: knight.id, starting_level: 5 } }
      faris = campaign.characters.find_by!(name: "Faris")
      expect(faris.motive).to eq("My sister is out there.")

      get campaign_path(campaign)
      expect(response.body).to include("motive--card", "My sister is out there.")
      get character_path(faris)
      expect(response.body).to include('class="motive"', "My sister is out there.")
      get world_compendium_job_path(world, knight)
      expect(response.body).to include("Desperation", "Unbroken Line")

      battle = BattleRecord.start!(campaign: campaign, characters: [ faris ], name: "Test", encounter: { "goblin" => 1 })
      get battle_path(battle)
      expect(response.body).to include("data-battle-player-cries-value=\"{&quot;#{faris.battle_unit_id}&quot;:&quot;My sister is out there.&quot;}\"")
    end

    it "lets the GM stock the bag and adjust gil" do
      post campaign_inventories_path(campaign), params: { inventory: { item_id: item.("potion").id, quantity: "4" } }
      expect(campaign.quantity_of(item.("potion"))).to eq(4)

      patch campaign_path(campaign), params: { campaign: { name: "Crystal Road", gil: "250" } }
      expect(campaign.reload.gil).to eq(250)
    end

    it "rests the party, and says so at the table, but not mid-battle" do
      bartz.update!(hp: 1, mp: 0)
      campaign.update!(time_of_day: "dusk")
      post campaign_rest_path(campaign)
      expect(bartz.reload.current_hp).to eq(bartz.stats["max_hp"])
      expect(bartz.current_mp).to eq(bartz.stats["max_mp"] / 2) # a bed brings the rest
      expect(campaign.messages.order(:id).last(2).map(&:body)).to eq([ "The party rests. Everyone is back to full HP, and half their MP.", "Day 2: dawn." ])

      bartz.update!(hp: 5)
      BattleRecord.start!(campaign: campaign, characters: [ bartz ], name: "Road", encounter: { "goblin" => 1 }, seed: 1)
      post campaign_rest_path(campaign)
      expect(flash[:alert]).to include("Not while a battle is on")
      expect(bartz.reload.hp).to eq(5)
    end

    it "makes camp on the road only: in a town with an inn, the party takes rooms" do
      village = world.location_templates.find_by!(slug: "village")
      seed = (1..50).find { |n| campaign.locations.new(location_template: village, seed: n).view["services"].any? { |sv| sv["kind"] == "inn" } }
      varn = campaign.map_nodes.create!(name: "Varn", kind: "town", x: 1, y: 1, visible: true, location: campaign.locations.create!(location_template: village, seed: seed))
      campaign.place_party!(varn)
      get campaign_path(campaign)
      expect(response.body).to include("Rooms at #{campaign.reload.inn_here['name']}")
      expect(response.body).not_to include("Make camp")
      post campaign_rest_path(campaign)
      expect(flash[:alert]).to include("The party is in Varn: take rooms at", "Camp is for the road.")
    end
  end

  describe "character creation" do
    it "creates a character at a level and job level" do
      get new_campaign_character_path(campaign)
      expect(response).to have_http_status(:ok)

      post campaign_characters_path(campaign), params: { character: {
        name: "Galuf", player_name: "Alex", job_id: knight.id, starting_level: "8", starting_job_level: "30"
      } }
      galuf = campaign.characters.find_by!(name: "Galuf")
      expect(response).to redirect_to(character_path(galuf))
      expect(galuf).to have_attributes(level: 8, player_name: "Alex")
      expect(galuf.native_abilities.map(&:name)).to eq([ "War Cry", "Armor Break", "Double Cut", "Shield Bash" ])
    end

    it "re-renders with errors" do
      post campaign_characters_path(campaign), params: { character: { name: "", job_id: knight.id, starting_level: "1" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("problem")
    end
  end

  describe "the character sheet" do
    it "shows level, job progress, the stat derivation, equipment and abilities" do
      get character_path(bartz)
      expect(response.body).to include("Bartz", "played by Sam", "Knight", "Lv</span> 1", "Base", "Gear", "Total",
                                       "War Cry", "Change archetype", "Free slots (1)")

      bartz.update!(user: make_user("Jo")) # an account beats the old player-name note
      get character_path(bartz)
      expect(response.body).to include("played by Jo")
      expect(response.body).not_to include("played by Sam")
    end

    it "equips from the bag, all slots in one form" do
      campaign.add_item!(item.("broadsword"))
      campaign.add_item!(item.("buckler"))
      patch character_equipment_path(bartz), params: { equipment: {
        weapon: item.("broadsword").id, shield: item.("buckler").id, head: "", body: "", accessory: ""
      } }
      expect(response).to redirect_to(character_path(bartz))
      expect(bartz.equipped.transform_values { |s| s.item.slug }).to eq("weapon" => "broadsword", "shield" => "buckler")

      patch character_equipment_path(bartz), params: { equipment: { weapon: "", shield: item.("buckler").id } }
      expect(bartz.equipped.keys).to eq([ "shield" ])
      expect(campaign.quantity_of(item.("broadsword"))).to eq(1)
    end

    it "refuses gear the job can't use, and changes nothing" do
      campaign.add_item!(item.("broadsword"))
      campaign.add_item!(item.("dagger"))
      patch character_equipment_path(bartz), params: { equipment: { weapon: item.("dagger").id, accessory: "" } }
      follow_redirect!
      expect(response.body).to include("Knight can&#39;t equip Dagger")
      expect(bartz.equipped).to be_empty
      expect(campaign.quantity_of(item.("dagger"))).to eq(1)
    end

    it "refuses an item in the wrong slot" do
      campaign.add_item!(item.("buckler"))
      patch character_equipment_path(bartz), params: { equipment: { weapon: item.("buckler").id } }
      follow_redirect!
      expect(response.body).to include("weapon can&#39;t hold that")
    end

    it "changes job and sets ability slots" do
      thief = world.jobs.find_by!(slug: "thief")
      patch character_job_path(bartz), params: { job_id: thief.id }
      expect(bartz.reload.job).to eq(thief)

      patch character_ability_slots_path(bartz), params: { ability_slots: { abilities: [ world.abilities.find_by!(slug: "war_cry").id ] } }
      expect(bartz.slotted_abilities.map(&:slug)).to eq(%w[war_cry])

      patch character_ability_slots_path(bartz), params: { ability_slots: { abilities: [ world.abilities.find_by!(slug: "fire").id ] } }
      follow_redirect!
      expect(response.body).to include("Fire not learned yet")
    end

    it "lets the GM grant EXP and ABP" do
      post character_grant_path(bartz), params: { grant: { exp: "1000", abp: "20" } }
      follow_redirect!
      expect(response.body).to include("Bartz gains 1000 EXP and 20 ABP.", "Level 11!", "Learned Armor Break.")
    end

    it "edits and removes a character, returning their gear to the bag" do
      patch character_path(bartz), params: { character: { name: "Butz", player_name: "Sam" } }
      expect(bartz.reload.name).to eq("Butz")

      campaign.add_item!(item.("broadsword"))
      bartz.equip!(item.("broadsword"))
      delete character_path(bartz)
      expect(response).to redirect_to(campaign_path(campaign))
      expect(Character.exists?(bartz.id)).to be(false)
      expect(campaign.quantity_of(item.("broadsword"))).to eq(1)
    end
  end

  describe "battle to character sheet" do
    it "brings the character in with their stats and HP, and writes the result back" do
      bartz.update!(hp: 50)
      post campaign_battles_path(campaign), params: { battle: {
        name: "Test", characters: [ bartz.id.to_s ], encounter: { "0" => { monster: "goblin", count: "1" } }
      } }
      battle = BattleRecord.last
      expect(battle.party.sole).to include("hp" => 50, "stats" => bartz.stats)

      post battle_seat_path(battle), params: { seat: "gm" }
      post battle_actions_path(battle), params: { gm: { op: "end_battle", result: "victory" } }
      get battle_panel_path(battle)
      expect(response.body).to include("Victory!", "Bartz</strong>: 30 EXP, 2 ABP", "Back to the table")
      expect(bartz.reload.exp).to eq(Stats::Growth.exp_for_level(5) + 30)
    end
  end
end
