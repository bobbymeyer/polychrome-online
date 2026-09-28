# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Flags and GM changes", type: :request do
  let!(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "Crystal Road") }
  let!(:bartz) { campaign.characters.create!(name: "Bartz", job: world.jobs.find_by!(slug: "knight")) }

  def sit(seat)
    post campaign_table_seat_path(campaign), params: { seat: seat }
  end

  describe "flags" do
    it "are the GM's to set, count and clear" do
      sit("gm")
      post campaign_flags_path(campaign), params: { flag: { key: "Crystals found", value: "1", public: "1" } }
      flag = campaign.flags.find_by!(key: "crystals_found")
      post bump_campaign_flag_path(campaign, flag), params: { by: 1 }
      expect(flag.reload.value).to eq("2")

      patch campaign_flag_path(campaign, flag), params: { flag: { value: "all four" } }
      expect(flag.reload.value).to eq("all four")
      post bump_campaign_flag_path(campaign, flag), params: { by: 1 }
      follow_redirect!
      expect(response.body).to include("isn&#39;t a number")

      delete campaign_flag_path(campaign, flag)
      expect(campaign.flags).to be_empty
    end

    # Each row's edit form and the new-flag form once shared id="flag_value",
    # so the "Value" label (and typing into it) hit the wrong field.
    it "gives every field on the campaign page its own id" do
      campaign.flags.create!(key: "a", value: "1")
      campaign.flags.create!(key: "b", value: "2")
      sit("gm")
      get campaign_path(campaign)
      ids = Nokogiri::HTML(response.body).css("[id]").map { |node| node["id"] }
      expect(ids.tally.select { |_, n| n > 1 }).to eq({})
    end

    it "reports bad keys" do
      sit("gm")
      post campaign_flags_path(campaign), params: { flag: { key: "9 lives", value: "x" } }
      follow_redirect!
      expect(response.body).to include("must start with a letter")
    end

    it "are hidden from players, except the public ones at the table" do
      campaign.flags.create!(key: "the_king_is_a_fake", value: "yes")
      campaign.flags.create!(key: "met_the_king", value: "yes", public: true)
      sit(bartz.id)

      post campaign_flags_path(campaign), params: { flag: { key: "cheat", value: "1" } }
      expect(response).to have_http_status(:forbidden)

      get campaign_path(campaign)
      expect(response.body).not_to include("the_king_is_a_fake", "met_the_king")
      get campaign_table_path(campaign)
      expect(response.body).to include("The party knows", "Met the king")
      expect(response.body).not_to include("fake")
    end
  end

  describe "GM changes" do
    let(:cave) do
      campaign.locations.create!(location_template: world.location_templates.find_by!(slug: "goblin_cave"), seed: 5)
    end

    it "lists every override with a revert, and reverting restores what was rolled" do
      cave.rename!("The Den")
      cave.place_boss!("ogre" => 1)
      added = cave.add_room!(name: "Hidden Vault", connect: cave.view["entrance"], decision: { "kind" => "treasure", "item" => "power_ring" })
      rolled = cave.generated

      sit("gm")
      get campaign_changes_path(campaign)
      expect(response.body).to include("Renamed to The Den", "Boss placed: 1 × Ogre", "Added room Hidden Vault", "Revert")

      post revert_location_path(cave), params: { kind: "room", key: added, return_to: campaign_changes_path(campaign) }
      expect(response).to redirect_to(campaign_changes_path(campaign))
      post revert_location_path(cave), params: { kind: "boss" }
      post revert_location_path(cave), params: { kind: "name" }
      expect(cave.reload.changes).to be_empty
      expect(cave.view).to eq(rolled)
    end

    it "reverts pinned and written-in townsfolk" do
      town = campaign.locations.create!(location_template: world.location_templates.find_by!(slug: "village"), seed: 5)
      key = town.view["npcs"].first["key"]
      town.pin!(key)
      galuf = campaign.npcs.create!(name: "Galuf", location: town)
      expect(town.changes.map { |c| c["summary"] }).to include(start_with("Pinned"), "Wrote in Galuf")

      sit("gm")
      town.changes.select { |c| c["kind"] == "npc" }.each do |change|
        post revert_location_path(town), params: { kind: "npc", key: change["key"] }
      end
      expect(campaign.npcs.where(location: town)).to be_empty
      expect(Npc.exists?(galuf.id)).to be(false)
    end

    it "is the GM's" do
      sit(bartz.id)
      get campaign_changes_path(campaign)
      expect(response).to have_http_status(:forbidden)
      post revert_location_path(cave), params: { kind: "name" }
      expect(response).to have_http_status(:forbidden)
    end
  end
end
