# frozen_string_literal: true

require "rails_helper"

RSpec.describe "The small things in authoring", type: :request do
  let(:world) { create_world }

  describe "a refused save" do
    it "links each problem to the section it is about, and takes focus" do
      post world_bestiary_monsters_path(world), params: { monster: { name: "Hollow", level: "2", stats: { str: "5" }, ai_script: { "0" => { use: "nothing" } } } }
      expect(response).to have_http_status(:unprocessable_content)
      errors = page.at(".form-errors[data-controller=summary]")
      expect(errors["tabindex"]).to eq("-1")
      expect(errors.css("a").to_h { |a| [ a["href"], a.text ] }.keys).to include("#stat-block", "#behavior")
      expect(page.css("[id='stat-block'], [id='behavior']").size).to eq(2) # and the links go somewhere
      expect(page.css("[id='art']").size).to eq(1)
    end

    it "marks the field of a plain attribute, and links to it" do
      post world_bestiary_monsters_path(world), params: { monster: { name: "", level: "2", stats: create_monster(world).stats } }
      expect(page.at(".form-errors a[href='#monster_name']").text).to include("Name")
      expect(page.at(".field_with_errors input#monster_name")).to be_present
    end
  end

  describe "an empty book" do
    it "says what it is for and offers the first entry to those who can add one" do
      get world_armory_items_path(world)
      expect(page.at(".empty-book").text.squish).to include("The Armory is empty.", "Items and equipment.")
      expect(page.at(".empty-book a.button").text).to eq("Add the first item")
      expect(page.at(".empty-book a.button")["href"]).to eq(new_world_armory_item_path(world))

      sign_out
      sign_in_as(make_user("Reader"))
      get world_armory_items_path(world)
      expect(page.at(".empty-book").text).to include("The Armory is empty.")
      expect(page.at(".empty-book a.button")).to be_nil
    end
  end

  describe "the monster form" do
    it "keeps the rule short and folds away the long explanations" do
      get new_world_bestiary_monster_path(world)
      expect(page.css("details.help > summary").map(&:text)).to eq([ "What Once, Says and When do", "What a phase keeps and changes" ])
      expect(page.at("details.help").text.squish).to include("A reaction comes at once")
    end

    it "shows the picture chosen at once, and says plainly when there is none" do
      get new_world_bestiary_monster_path(world)
      expect(page.at("fieldset#art[data-controller=image-preview] input[type=file]")["data-action"]).to eq("image-preview#show")
      expect(page.at("fieldset#art [data-image-preview-target=slot] figure")).to be_present
      expect(page.at("fieldset#art .hint").text).to include("No picture yet", "baible")
    end
  end

  describe "flags" do
    let!(:world) { base_world }
    let(:campaign) { base_campaign(name: "Pulp", gm: @admin) }

    before { sit(campaign, "gm") }

    it "traces a flag to the scene whose choice sets it, and names the ones still to come" do
      campaign.scenes.create!(name: "The gate", script: "? Trust Cid | Refuse -> trusted_cid")
      get campaign_prep_path(campaign)
      expect(page.at("#flags").text.squish).to include("Your scenes' choices will set: trusted_cid")

      campaign.set_flag!("trusted_cid", "Trust Cid")
      get campaign_prep_path(campaign)
      expect(page.at("#flags").text.squish).to include("Set by a choice in The gate.")
      expect(page.at("#flags").text).not_to include("Your scenes' choices will set")
      get new_campaign_scene_path(campaign)
      expect(page.at(".script-paste").text.squish).to include("Flags so far: trusted_cid")
    end
  end
end
