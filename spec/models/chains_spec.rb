# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Secrets as chains of clues" do
  let(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "Crystal Road") }
  let(:village) { world.location_templates.find_by!(slug: "village") }
  let!(:crossing) { campaign.map_nodes.create!(name: "Crossing", kind: "field", x: 1, y: 1, visible: true) }
  let!(:hollin) do
    campaign.map_nodes.create!(name: "Hollin", kind: "town", x: 5, y: 5, visible: true, location: campaign.locations.create!(location_template: village, seed: 3))
  end
  let!(:rook) { create_character(campaign, name: "Rook") }
  let(:mayor) { campaign.npcs.create!(name: "Mayor Hale", location: hollin.location) }
  let(:steps) do
    <<~STEPS
      Why is the mayor's lamp lit at midnight?
      Someone leaves the mayor's house before dawn, by the back gate.
      The mayor's sick, and the lamp is for the doctor. | Mara Vell
    STEPS
  end
  let!(:secret) { campaign.secrets.create!(body: "The mayor pays the goblins.", key: "mayors_lamp", steps: steps, location: hollin.location, npc: mayor) }

  def table = campaign.messages.where(scope: "table").pluck(:body)
  def offers = campaign.messages.where(scope: "gm").select { |m| m.data.dig("offer", "clue") }

  before do
    world.generator_tables.where(kind: %w[arrivals events]).destroy_all
    campaign.update!(current_node: crossing)
  end

  it "reads clues, vaguest first, with who tells them, and says what it can't read" do
    expect(secret.clues).to eq([ Clue.new(text: "Why is the mayor's lamp lit at midnight?", teller: nil),
                                 Clue.new(text: "Someone leaves the mayor's house before dawn, by the back gate.", teller: nil),
                                 Clue.new(text: "The mayor's sick, and the lamp is for the doctor.", teller: "Mara Vell") ])
    expect(campaign.secrets.new(body: "x", steps: "| Mara").valid?).to be(false)
    expect(campaign.secrets.new(body: "x", key: "mayors_lamp").valid?).to be(false) # taken
  end

  it "comes out a clue at a time, wherever it's found, then the secret itself" do
    secret.find_clue!
    secret.find_clue!(by: "Rook's Ask Around")
    secret.find_clue!(by: "In Hollin")
    expect(table).to eq([ "A question: Why is the mayor's lamp lit at midnight?",
                          "A clue (Rook's Ask Around): Someone leaves the mayor's house before dawn, by the back gate.",
                          "A clue (In Hollin): Mara Vell says: The mayor's sick, and the lamp is for the doctor." ])
    expect(secret.reload).not_to be_revealed
    expect(campaign.moment).to include("mayors_lamp" => 3, "mayors_lamp_known" => false)

    Outcome.of("uncover").apply!(campaign, by: "Vivi")
    expect(secret.reload).to be_revealed
    expect(table.last).to eq("Vivi: the party learns: The mayor pays the goblins.")
    expect(campaign.moment).to include("mayors_lamp_known" => true)
    expect { secret.find_clue! }.to raise_error(Refusal, "The party already knows that")
  end

  it "offers the next clue to the GM on arriving where it is, once until it's found, and finds it when they say" do
    road = campaign.map_edges.create!(from_node: crossing, to_node: hollin)
    campaign.travel!(road)
    note = offers.sole
    expect(note.body).to eq("A question at Hollin: Why is the mayor's lamp lit at midnight?")

    campaign.place_party!(crossing)
    campaign.place_party!(hollin)
    expect(offers.size).to eq(1) # still waiting

    campaign.say_offer!(note)
    expect(table.last).to eq("A question (In Hollin): Why is the mayor's lamp lit at midnight?")
    expect(secret.reload.found).to eq(1)
    expect { campaign.say_offer!(note.reload) }.to raise_error(Refusal, "Already said.")

    campaign.place_party!(crossing)
    campaign.place_party!(hollin)
    expect(offers.last.body).to eq("A clue at Hollin, toward “Why is the mayor's lamp lit at midnight?”: Someone leaves the mayor's house before dawn, by the back gate.")
  end

  it "offers a clue when the person it's about speaks, and won't find one that's been found since" do
    campaign.messages.create!(body: "Evening.", speaker: mayor)
    note = offers.sole
    expect(note.body).to eq("A question from Mayor Hale: Why is the mayor's lamp lit at midnight?")
    secret.find_clue!
    expect { campaign.say_offer!(note) }.to raise_error(Refusal, "The party has found that one already.")
  end

  it "shows the party what it's asking, with the clues so far, and the GM a chain's next step in the moves panel" do
    secret.find_clue!
    secret.find_clue!
    html = ApplicationController.render(partial: "campaigns/tables/party_knows", locals: { campaign: campaign, gm: false })
    expect(html).to include("Why is the mayor&#39;s lamp lit at midnight?", "Someone leaves the mayor&#39;s house before dawn")
    expect(campaign.chains).to eq([ secret ])
  end

  it "is written on a front's secret and comes with it into a campaign" do
    expect(world.world_fronts.find_by!(name: "The Barrow Lord's silver").secrets.find_by!(key: "goblin_silver").steps).to start_with("Why do the goblins")
    front = world.world_fronts.create!(name: "The lamp", secrets: [ { "body" => "The mayor pays the goblins.", "key" => "mayors_lamp", "steps" => steps } ])
    fresh = world.campaigns.create!(name: "Fresh")
    front.deal!(fresh)
    expect(fresh.secrets.find_by!(body: "The mayor pays the goblins.")).to have_attributes(key: "mayors_lamp", steps: steps.strip, found: 0)
  end
end
