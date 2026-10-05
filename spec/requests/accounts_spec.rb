# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Accounts", type: :request do
  describe "signing up and in", signed_out: true do
    it "sends strangers to sign in, but leaves the health check open" do
      get root_path
      expect(response).to redirect_to(new_session_path)
      get rails_health_check_path
      expect(response).to have_http_status(:ok)
    end

    it "makes the first account the admin, and nobody after" do
      get new_registration_path
      expect(response.body).to include("Nobody is here yet")

      post registration_path, params: { user: { name: "Bobby", email_address: "Bobby@Example.com ", password: "long enough pw", password_confirmation: "long enough pw" } }
      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to include("you're the admin")
      bobby = User.find_by!(email_address: "bobby@example.com")
      expect(bobby).to be_admin

      sign_out
      post registration_path, params: { user: { name: "Lenna", email_address: "lenna@example.com", password: "long enough pw", password_confirmation: "long enough pw" } }
      expect(User.find_by!(name: "Lenna")).not_to be_admin
      follow_redirect!
      expect(response.body).to include("Lenna")
    end

    it "rejects a short password or a taken email" do
      make_user("Taken")
      post registration_path, params: { user: { name: "X", email_address: "x@example.com", password: "short", password_confirmation: "short" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Password is too short")
    end

    it "signs in and out" do
      user = make_user("Faris")
      post session_path, params: { email_address: user.email_address, password: "wrong" }
      expect(response).to redirect_to(new_session_path)

      sign_in_as(user)
      get root_path
      expect(response).to have_http_status(:ok)
      sign_out
      get root_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "what a player can and can't do" do
    let!(:world) { base_world }
    let(:campaign) { world.campaigns.create!(name: "Crystal Road", gm: @admin) }
    let!(:lenna) { make_user("Lenna") }
    let(:goblin) { world.monsters.find_by!(slug: "goblin") }

    before { sign_in_as(lenna) }

    it "reads the books but can't write them, or the world's art" do
      get world_bestiary_monster_path(world, goblin)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(">Edit<", "The prompt, in layers")

      patch world_bestiary_monster_path(world, goblin), params: { monster: { name: "Hobgoblin" } }
      expect(response).to redirect_to(root_path)
      expect(goblin.reload.name).to eq("Goblin")

      get world_art_direction_path(world)
      expect(response).to redirect_to(root_path)
      expect { post world_art_batches_path(world), params: { entry_type: "monster", entry_slug: "goblin" } }.not_to change(ArtBatch, :count)
      get world_path(world)
      expect(response.body).to include("Copy this world")
      expect(response.body).not_to include("Edit world")
    end

    it "runs their own game: a campaign they GM, and a world of their own whose books they and their GMs can change" do
      post world_campaigns_path(world), params: { campaign: { name: "Lenna's Road" } }
      expect(Campaign.find_by!(name: "Lenna's Road").gm).to eq(lenna)

      post worlds_path, params: { world: { name: "Ashfall", slug: "ashfall" }, copy_from: world.slug }
      ashfall = World.find_by!(slug: "ashfall")
      expect(ashfall.owner).to eq(lenna)
      ash_goblin = ashfall.monsters.find_by!(slug: "goblin")
      patch world_bestiary_monster_path(ashfall, ash_goblin), params: { monster: { name: "Ash Goblin" } }
      expect(ash_goblin.reload.name).to eq("Ash Goblin")
      get world_path(ashfall)
      expect(response.body).to include("Edit world")

      # A GM running a campaign in her world can change it too; another GM can't.
      faris = make_user("Faris")
      ashfall.campaigns.create!(name: "Faris's Run", gm: faris)
      sign_in_as(faris)
      patch world_bestiary_monster_path(ashfall, ash_goblin), params: { monster: { name: "Cinder Goblin" } }
      expect(ash_goblin.reload.name).to eq("Cinder Goblin")
      sign_in_as(make_user("Galuf"))
      patch world_bestiary_monster_path(ashfall, ash_goblin), params: { monster: { name: "Nope" } }
      expect(ash_goblin.reload.name).to eq("Cinder Goblin")
      expect(flash[:alert]).to include("Copy it to make your own")
    end

    it "makes their own character, at the party's lowest level, and only they (and the GM) run it" do
      campaign.characters.create!(name: "Bartz", job: world.jobs.find_by!(slug: "knight"), starting_level: 5)
      post campaign_characters_path(campaign), params: { character: { name: "Lenna", job_id: world.jobs.find_by!(slug: "white_mage").id, starting_level: 99 } }
      mine = campaign.characters.find_by!(name: "Lenna")
      expect(mine.user).to eq(lenna)
      expect(mine.level).to eq(5)

      bartz = campaign.characters.find_by!(name: "Bartz")
      bartz.update!(user: make_user("Someone"))
      patch character_equipment_path(bartz), params: { equipment: { weapon: "" } }
      expect(flash[:alert]).to eq("That's not yours to change.")
      get character_path(bartz)
      expect(response.body).not_to include("Update equipment")
      get character_path(mine)
      expect(response.body).to include("Update equipment")
      expect(response.body).not_to include("Grant EXP")
    end

    it "sits only as their own or an unclaimed character, never as the GM, and claims by sitting" do
      taken = campaign.characters.create!(name: "Bartz", job: world.jobs.find_by!(slug: "knight"), user: make_user("Someone"))
      free = campaign.characters.create!(name: "Galuf", job: world.jobs.find_by!(slug: "monk"))

      get campaign_table_path(campaign)
      seats = response.body[%r{<h2>Take a seat</h2>.*?</section>}m]
      expect(seats).to include("Galuf (unclaimed)")
      expect(seats).not_to include(">Game Master<", ">Bartz<")

      post campaign_table_seat_path(campaign), params: { seat: "gm" }
      post campaign_table_seat_path(campaign), params: { seat: taken.id }
      get campaign_table_path(campaign)
      expect(response.body).to include("Take a seat")

      post campaign_table_seat_path(campaign), params: { seat: free.id }
      expect(free.reload.user).to eq(lenna)
      get campaign_table_path(campaign)
      expect(Nokogiri::HTML(response.body).at("#table_party li.is-you").text).to include("Galuf")

      # A GM power, tried by hand, is refused.
      post campaign_flags_path(campaign), params: { flag: { key: "cheat", value: "1" } }
      expect(response).to have_http_status(:forbidden)
    end

    it "can't take the GM seat in a battle, or someone else's unit" do
      battle = start_battle(campaign: campaign)
      bartz, faris = campaign.characters.order(:created_at).to_a
      bartz.update!(user: make_user("Someone"))
      faris.update!(user: lenna)

      # Her only character is the obvious seat: she's already in it.
      get battle_panel_path(battle)
      expect(response.body).to include("Seated as <strong>Faris</strong>")
      expect(response.body).not_to include("Game Master")

      post battle_seat_path(battle), params: { seat: "gm" }
      post battle_seat_path(battle), params: { seat: bartz.battle_unit_id }
      get battle_panel_path(battle)
      expect(response.body).to include("Seated as <strong>Faris</strong>")
      post battle_actions_path(battle), params: { gm: { op: "execute_round" } }
      expect(battle.reload.round).to eq(1)
    end
  end

  describe "a campaign's GM" do
    let!(:world) { base_world }
    let(:campaign) { world.campaigns.create!(name: "Crystal Road", gm: @admin) }
    let!(:krile) { make_user("Krile") }

    it "is whoever an admin makes it, and runs that campaign (portraits included) but not the world" do
      patch campaign_path(campaign), params: { campaign: { gm_id: krile.id } }
      expect(campaign.reload.gm).to eq(krile)

      sign_in_as(krile)
      post campaign_table_seat_path(campaign), params: { seat: "gm" }
      get campaign_table_path(campaign)
      expect(response.body).to include("At the table as <strong>GM</strong>")
      patch campaign_path(campaign), params: { campaign: { name: "The Void", gm_id: krile.id } }
      expect(campaign.reload.name).to eq("The Void")

      cid = campaign.npcs.create!(name: "Cid")
      expect {
        post world_art_batches_path(world), params: { entry_type: "portrait", owner_type: "npc", owner_id: cid.id, expression: "neutral", count: 1 }
      }.to change(ArtBatch, :count).by(1)
      expect { post world_art_batches_path(world), params: { entry_type: "monster", entry_slug: "goblin" } }.not_to change(ArtBatch, :count)

      other = world.campaigns.create!(name: "Someone else's")
      patch campaign_path(other), params: { campaign: { name: "Mine now" } }
      expect(other.reload.name).to eq("Someone else's")
    end
  end

  describe "the Accounts page" do
    it "is the admins' to promote and remove accounts, never the last admin" do
      lenna = make_user("Lenna")
      get users_path
      expect(response.body).to include("Lenna", "Admin")

      patch user_path(lenna), params: { user: { admin: true } }
      expect(lenna.reload).to be_admin
      patch user_path(lenna), params: { user: { admin: false } }
      patch user_path(@admin), params: { user: { admin: false } }
      expect(flash[:alert]).to include("last admin")
      expect(@admin.reload).to be_admin

      delete user_path(lenna)
      expect(User.exists?(lenna.id)).to be(false)

      sign_in_as(make_user("Nobody"))
      get users_path
      expect(response).to redirect_to(root_path)
    end
  end
end
