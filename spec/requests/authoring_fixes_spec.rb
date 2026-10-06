# frozen_string_literal: true

require "rails_helper"

# What a second author tripped over writing Greenware, fixed.
RSpec.describe "Authoring fixes", type: :request do
  let(:world) { base_world }
  let(:campaign) { create_campaign(world: world) }

  it "names the stage's colours when a colour isn't one" do
    figure = world.world_figures.new(name: "Painted Man", colour: "#e8702a")
    expect(figure).not_to be_valid
    expect(figure.errors.full_messages.first).to include("must be one of the stage's colours", "sun_yellow")
  end

  describe "typed blows" do
    it "is the author's call, not a reading of the stats" do
      thief = world.jobs.find_by!(slug: "thief")
      thief.update!(typed_attack: true)
      expect(thief.battle_type).to include("attack_type" => "dark")
      thief.update!(typed_attack: false)
      expect(thief.battle_type).not_to have_key("attack_type")
      expect(world.jobs.find_by!(slug: "freelancer").battle_type).not_to have_key("attack_type") # the plain type, either way
    end

    it "is set from the archetype form and said on its page" do
      sign_in_as(make_user("Author", admin: true))
      thief = world.jobs.find_by!(slug: "thief")
      patch world_compendium_job_path(world, thief), params: { job: { typed_attack: "0" } }
      expect(thief.reload.typed_attack).to be(false)
      get world_compendium_job_path(world, thief)
      expect(response.body).to include("Attack and the signature command are plain blows")
      patch world_compendium_job_path(world, thief), params: { job: { typed_attack: "1" } }
      get world_compendium_job_path(world, thief)
      expect(response.body).to include("strike as dark")
    end
  end

  it "tries a creature against a level-5 party from its page" do
    sign_in_as(make_user("Reader"))
    goblin = world.monsters.find_by!(slug: "goblin")
    get world_bestiary_monster_path(world, goblin)
    expect(response.body).to include("Try it against a level-5 party")
    get world_bestiary_monster_trial_path(world, goblin, count: 3)
    expect(response.body).to include("3 × Goblin", "The party won", "Knight")
  end

  it "warns when the plain type is weak to several others, and talks of arts of the land, not Geomancers" do
    sign_in_as(make_user("Reader"))
    get world_types_path(world)
    expect(response.body).to include("an art of the land")
    expect(response.body).not_to include("Geomancer's arts")

    world.update!(terrain_types: {}, damage_types: [ { "slug" => "clay", "name" => "Clay", "colour" => "#b5651d", "against" => {} },
                                  { "slug" => "fire", "name" => "Fire", "colour" => "#e8702a", "against" => { "clay" => 200 } },
                                  { "slug" => "water", "name" => "Water", "colour" => "#4f82e8", "against" => { "clay" => 200 } } ])
    get world_types_path(world)
    expect(response.body).to include("Clay is the plain type", "2 of 3 types land double")
  end

  it "warns when a template pools several tables of one kind" do
    sign_in_as(make_user("Author", admin: true))
    cave = world.location_templates.find_by!(slug: "goblin_cave")
    world.generator_tables.create!(slug: "more_rooms", name: "More rooms", kind: "rooms", entries: [ { "text" => "Annex" } ])
    cave.update!(config: cave.config.merge("tables" => cave.config["tables"] + [ "more_rooms" ]))
    expect(cave.crowded_kinds).to eq([ "rooms" ])
    get edit_world_gazetteer_location_template_path(world, cave)
    expect(response.body).to include("draws on more than one table of rooms")
  end

  it "lets the GM take the world's tables again for a place the party has been to, keeping its seed" do
    gm = make_user("GM")
    campaign.update!(gm: gm)
    sign_in_as(gm)
    sit(campaign, "gm")
    expect(response).to have_http_status(:redirect)
    campaign.set_out!(from_the_setting: true)
    tule = campaign.map_nodes.find_by!(name: "Tule").location
    tule.remember!
    expect(tule.overrides).to have_key("tables")
    get location_path(tule)
    expect(response.body).to include("Reroll")
    expect(response.body).to include("tables again")

    seed = tule.seed
    delete location_memory_path(tule)
    expect(tule.reload.overrides).not_to have_key("tables")
    expect(tule.seed).to eq(seed)
    expect(flash[:notice]).to include("Rolled from the world's tables")
    expect { tule.forget_tables! }.to raise_error(Refusal)
  end

  it "says a rest begun as the day begins is a rest, not a night, and spending time returns what the table heard" do
    campaign.set_out!(from_the_setting: true)
    create_character(campaign, name: "Bartz")
    expect(campaign.sleep!).to end_with("The day has only begun: a rest, not a night.")
    expect(campaign.reload.day).to eq(1)
    campaign.update!(time_of_day: "night")
    expect(campaign.sleep!).not_to include("not a night")

    tule = campaign.current_node
    tule.world_place.update!(activities: "Sweep the yard (any, money 5): Dust.")
    expect(campaign.spend_time!(tule, "Sweep the yard")).to eq("Tule: Sweep the yard.")
  end

  it "keeps a lost name at the start of its sentence" do
    expect(Past.new({ "was" => "mine", "lost" => [ "the first crew" ] }).to_s).to include("The first crew never came out.")
  end
end
