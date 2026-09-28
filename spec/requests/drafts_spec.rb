# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/base_world")

RSpec.describe "Suggestions from the language model (Draft)", type: :request do
  include ActiveJob::TestHelper

  let!(:world) { Seeds::BaseWorld.run }
  let(:campaign) { world.campaigns.create!(name: "Pulp", gm: @admin) }
  let(:village) { world.location_templates.find_by!(slug: "village") }
  let(:town) { campaign.locations.create!(location_template: village, seed: 11) }
  let!(:node) { campaign.map_nodes.create!(name: "Tule", kind: "town", x: 100, y: 100, visible: true, location: town) }
  let!(:cid) { campaign.npcs.create!(name: "Cid", title: "airship engineer", description: "Owes money to everyone.") }

  before do
    allow(Llm).to receive(:enabled?).and_return(true)
    post campaign_table_seat_path(campaign), params: { seat: "gm" }
  end

  # Ask, then let the job run against a scripted model. Returns the draft.
  def suggest(owner, kind, reply, target: nil, **fields)
    path = owner.is_a?(Campaign) ? campaign_drafts_path(owner) : world_drafts_path(owner)
    post path, params: { kind: kind, target: target&.to_global_id&.to_s, draft: fields }.compact
    draft = Draft.latest(owner, kind, target)
    @llm = ScriptedLlm.new(reply)
    DraftJob.new.perform(draft, client: @llm)
    draft.reload
  end

  def keep(draft, index = 0)
    owner = draft.owner
    post(owner.is_a?(Campaign) ? keep_campaign_draft_path(owner, draft, item: index) : keep_world_draft_path(owner, draft, item: index))
  end

  it "suggests secrets from what's in the campaign, and keeps the one the GM wants" do
    draft = suggest(campaign, "secrets", <<~REPLY, idea: "the mill")
      Here you go!
      ```json
      {"secrets": [{"text": "Cid sold the mill's deed twice.", "place": "Tule", "person": "cid"},
                   {"text": "The miller is alive.", "place": "Nowhere", "person": null}]}
      ```
    REPLY
    expect(@llm.asked.sole[:user]).to include("Cid, airship engineer: Owes money to everyone.", "Tule (town)", "The GM's idea: the mill")
    expect(draft).to have_attributes(status: "done")
    expect(draft.items.first).to eq("text" => "Cid sold the mill's deed twice.", "place" => town.name, "person" => "Cid")
    expect(draft.items.second).to eq("text" => "The miller is alive.")

    get campaign_path(campaign)
    expect(response.body).to include("Suggest secrets", "Cid sold the mill&#39;s deed twice.")

    keep(draft)
    expect(campaign.secrets.sole).to have_attributes(body: "Cid sold the mill's deed twice.", location: town, npc: cid)
    expect(draft.reload.items.first["kept"]).to be(true)
    keep(draft)
    expect(flash[:alert]).to eq("Already kept")
  end

  it "suggests clocks, keeping only triggers it knows" do
    draft = suggest(campaign, "clocks", '{"clocks": [{"name": "The Syndicate takes the docks", "segments": 20, ' \
                                        '"ticks_on": ["rest", "moonrise"], "when_full": "Smoke over the harbour.", "public": true}]}')
    expect(draft.items.sole).to eq("name" => "The Syndicate takes the docks", "segments" => 12, "triggers" => [ "rest" ],
                                   "full_line" => "Smoke over the harbour.", "public" => true)
    keep(draft)
    expect(campaign.clocks.sole).to have_attributes(name: "The Syndicate takes the docks", segments: 12, triggers: [ "rest" ], public: true)
  end

  it "puts a suggested scene on the new scene form, flagging lines to fix" do
    draft = suggest(campaign, "scene", '{"name": "The debt", "script": "Cid (worried): I owe them.\nMara: Then pay.\n? Help Cid | Walk away -> helped_cid"}')
    expect(@llm.asked.sole[:system]).to include("Use only names from the cast")
    item = draft.items.sole
    expect(item["problems"].sole).to include("Mara isn't in the cast")
    keep(draft)
    expect(response).to redirect_to(new_campaign_scene_path(campaign, scene: { name: "The debt", script: item["script"] }))
    follow_redirect!
    expect(response.body).to include("The debt", "Cid (worried): I owe them.")
  end

  it "suggests modes for a place, only with services it has" do
    draft = suggest(campaign, "mode", '{"modes": [{"name": "Plague", "line": "Bells, and no one answers.", "closed": ["inn", "casino"], ' \
                                      '"music": "dungeon", "art": "empty streets, chalk marks on doors"}]}', target: town)
    expect(@llm.asked.sole[:user]).to include("The place: #{town.name}")
    closed = draft.items.sole["closed"]
    expect(closed).not_to include("casino")
    keep(draft)
    expect(town.reload.modes.sole).to include("name" => "Plague", "music" => "dungeon", "art" => "empty streets, chalk marks on doors")
  end

  it "keeps prep drafts to the campaign's GM" do
    sign_in_as(make_user("Player"))
    post campaign_drafts_path(campaign), params: { kind: "secrets" }
    expect(response).to have_http_status(:forbidden)
  end

  describe "world building" do
    let(:goblin) { world.monsters.find_by!(slug: "goblin") }

    it "suggests an entry's description in its book's voice" do
      draft = suggest(world, "description", '{"descriptions": ["Small, green and owed money.", "Knife first, questions never."]}', target: goblin)
      expect(@llm.asked.sole[:user]).to include("The entry: Goblin, a monster.", "Others in the same book")
      keep(draft, 1)
      expect(goblin.reload.description).to eq("Knife first, questions never.")
    end

    it "names an ability family's tiers and puts them on the family form" do
      draft = suggest(world, "family", '{"tiers": [{"name": "Frost", "description": "A bite of cold."}, {"name": "Frostra", "description": "Colder."}, ' \
                                       '{"name": "Frostaga", "description": "Everyone shivers."}, {"name": "Frostaja", "description": "Winter itself."}]}',
                      root: "Frost", shape: "caster", type: "ice")
      keep(draft)
      follow_redirect!
      expect(response.body).to include('value="Frostra"', 'value="Winter itself."')
      post world_grimoire_families_path(world), params: { family: { root: "Frost", shape: "caster", type: "ice",
                                                                    tiers: { "0" => { name: "Frost", description: "A bite of cold." } } } }
      expect(world.abilities.find_by!(name: "Frost").description).to eq("A bite of cold.")
    end

    it "suggests a setting's types, skills and jobs; types and skills can be kept" do
      draft = suggest(world, "setting", '{"types": [{"name": "Rust", "colour": "#8b4513"}], ' \
                                        '"skills": [{"name": "Haggling", "stat": "spr", "description": "Get the price down."}, {"name": "Bad", "stat": "luck"}], ' \
                                        '"jobs": [{"name": "Tidecaller", "description": "Pulls the sea about.", "type": "Water"}]}',
                      pitch: "Rusting port cities.")
      expect(draft.items.map { |i| [ i["section"], i["name"] ] }).to eq([ %w[type Rust], %w[skill Haggling], %w[job Tidecaller] ])
      keep(draft, 0)
      expect(world.reload.type_chart.name("rust")).to eq("Rust")
      keep(draft, 1)
      expect(world.reload.skill("haggling")).to include("stat" => "spr")
      keep(draft, 2)
      expect(flash[:alert]).to include("Compendium")
      get world_path(world)
      expect(response.body).to include("Tidecaller", "make it in the Compendium")
    end

    it "says what went wrong when the model doesn't help" do
      draft = suggest(world, "description", "I'd rather not.", target: goblin)
      expect(draft).to have_attributes(status: "failed", error: "The language model didn't answer in JSON")
      get world_bestiary_monster_path(world, goblin)
      expect(response.body).to include("The language model didn&#39;t answer in JSON")
    end
  end

  it "offers nothing when no language model is set up" do
    allow(Llm).to receive(:enabled?).and_return(false)
    get campaign_path(campaign)
    expect(response.body).not_to include("Suggest secrets")
  end
end
