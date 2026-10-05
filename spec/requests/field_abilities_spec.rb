# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Field abilities", type: :request do
  let!(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "Crystal Road", gm: @admin) }
  let(:job) { ->(slug) { world.jobs.find_by!(slug: slug) } }
  let(:tule) { campaign.map_nodes.create!(name: "Tule", kind: "town", x: 100, y: 100, visible: true) }
  let(:ruins) { campaign.map_nodes.create!(name: "Ruins", kind: "dungeon", x: 400, y: 300) }

  def hero(slug, name: slug.humanize)
    campaign.characters.create!(name: name, job: job.(slug), starting_level: 10, starting_gear: false)
  end

  def sit(seat)
    post campaign_table_seat_path(campaign), params: { seat: seat.respond_to?(:id) ? seat.id : seat }
  end

  # The player asks; the GM rolls it at an easy difficulty.
  def use!(character, difficulty: "easy")
    sit(character)
    post campaign_field_uses_path(campaign)
    raise flash[:alert] if flash[:alert]
    sit("gm")
    patch campaign_field_use_path(campaign, campaign.field_uses.last), params: { difficulty: difficulty }
    campaign.field_uses.last.reload
  end

  # Until the dice come in: each use is once per rest.
  def succeed(character, &setup)
    20.times do
      setup&.call
      use = use!(character)
      return use if use.result["success"]

      character.reload.update!(field_used: false)
    end
    raise "never came in"
  end

  it "shows a character their field ability, lets them ask, and shows the GM the request" do
    kim = hero("thief", name: "Kim")
    sit(kim)
    get campaign_table_path(campaign)
    row = Nokogiri::HTML(response.body).at("#field_ability .pick-table .pick-row") # a row, like the ways and the vote
    expect(row.at("button.pick-row__act").text).to eq("Use Pick Lock")
    expect(row.at(".pick-row__note").text).to include("Thievery", "once per rest")
    expect(row.at(".pick-row__cost").text).to eq("ask")
    get campaign_table_path(campaign, view: "controller")
    moves = Nokogiri::HTML(response.body).at("section.your-moves")
    expect(moves.at("#field_ability").text).to include("Use Pick Lock") # with the controller's other moves

    post campaign_field_uses_path(campaign)
    expect(campaign.messages.last.body).to eq("Kim wants to Pick Lock.")
    get campaign_table_path(campaign)
    expect(response.body).to include("Pick Lock: asked for. Waiting on the GM…")
    expect(response.body).not_to include("Use Pick Lock") # not a move you can make now

    sit("gm")
    get campaign_table_path(campaign)
    expect(response.body).to include("Asked for", "Kim</strong> wants to <strong>Pick Lock", "Roll it", "Not now")
  end

  it "rolls on the GM's yes with the skill and the job's bonus, once per rest, back after a rest" do
    kim = hero("thief", name: "Kim")
    use = use!(kim, difficulty: "hard")
    check = campaign.messages.where(cue: "check").last
    expect(check.body).to match(/\AKim: Pick Lock \(Thievery, hard, \+15 Thief\)\. needed \d+ or over · rolled \d+/)
    expect(use).to have_attributes(status: "done", difficulty: "hard")
    expect(kim.reload).to be_field_used

    sit(kim)
    post campaign_field_uses_path(campaign)
    expect(flash[:alert]).to eq("Kim has used Pick Lock since the last rest")
    campaign.sleep!
    expect(kim.reload).not_to be_field_used
  end

  it "costs nothing when the GM says no" do
    kim = hero("thief", name: "Kim")
    sit(kim)
    post campaign_field_uses_path(campaign)
    sit("gm")
    patch campaign_field_use_path(campaign, campaign.field_uses.last), params: { verdict: "veto", line: "The guards are watching." }
    expect(campaign.messages.last.body).to eq("Not now, Kim. The guards are watching.")
    expect(kim.reload).not_to be_field_used
  end

  it "only lets the GM say yes, and a player ask only as themselves" do
    kim = hero("thief", name: "Kim")
    sit(kim)
    post campaign_field_uses_path(campaign)
    patch campaign_field_use_path(campaign, campaign.field_uses.last), params: { difficulty: "easy" }
    expect(campaign.field_uses.last).to be_pending
  end

  describe "outcomes" do
    it "reveals the places next to the party" do
      campaign.place_party!(tule)
      campaign.map_edges.create!(from_node: tule, to_node: ruins)
      succeed(hero("dragoon", name: "Kain"))
      expect(ruins.reload).to be_visible
      expect(campaign.messages.last.body).to eq("Kain scouts ahead: Ruins comes into view.")
    end

    it "avoids the encounter on the road, and reads it first" do
      encounter = { "table" => "Road", "monsters" => { "goblin" => 2 } }
      campaign.update!(pending_encounter: encounter)
      succeed(hero("black_mage", name: "Vivi")) { campaign.update!(pending_encounter: encounter) }
      expect(campaign.reload.known_affinities["goblin"]).to include("fire" => "weak", "types" => [ "normal" ])

      succeed(hero("red_mage", name: "Terra")) { campaign.update!(pending_encounter: encounter) }
      expect(campaign.reload.pending_encounter).to be_nil
      expect(campaign.messages.last.body).to eq("Terra gets the party past without a fight.")
    end

    it "won't sneak past or read an encounter that isn't there" do
      sit(hero("red_mage", name: "Terra"))
      post campaign_field_uses_path(campaign)
      expect(flash[:alert]).to match(/no encounter on the road/)
    end

    it "finds an item, restores the party, and makes the next road safe" do
      succeed(hero("freelancer", name: "Butz"))
      expect(campaign.bag.sum(&:quantity)).to eq(1)

      rosa = hero("white_mage", name: "Rosa")
      rosa.update!(hp: 1, mp: 0)
      succeed(rosa) { rosa.update!(hp: 1, mp: 0) }
      expect(rosa.reload.current_hp).to eq(1 + (rosa.stats["max_hp"] * 40 / 100))

      succeed(hero("geomancer", name: "Gaia"))
      campaign.place_party!(tule)
      edge = campaign.map_edges.create!(from_node: tule, to_node: ruins, state: "dangerous", encounter_table: world.encounter_tables.first)
      expect(campaign.reload.travel!(edge)).to be_nil
      expect(campaign.messages.where(scope: "table").last.body).to eq("The way is safe: nothing troubles the party on the road.")
      expect(campaign.reload).not_to be_safe_road
    end
  end
end
