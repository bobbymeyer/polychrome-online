# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Simulating a fight", type: :request do
  let(:campaign) { base_campaign }
  let!(:cloud) { base_character(campaign, name: "Cloud", job: "knight", starting_level: 3) }
  let!(:vivi) { base_character(campaign, name: "Vivi", job: "black_mage", starting_level: 3) }

  def simulate(**choices)
    get campaign_simulation_path(campaign), params: { simulation: choices }
  end

  it "plays a fight out many times for the GM, from Prep, and keeps nothing" do
    get campaign_prep_path(campaign)
    expect(page.at("a[href='#{campaign_simulation_path(campaign)}']").text).to eq("Simulate")
    get campaign_simulation_path(campaign)
    expect(page.at(".simulation__result")).to be_nil # nothing asked yet

    expect do
      simulate(characters: [ cloud.id, vivi.id ], encounter: { "0" => { monster: "goblin", count: "3" } }, runs: "6", tactics: "full", rested: "1")
    end.not_to change { [ BattleRecord.count, Message.count ] }
    expect(response).to have_http_status(:ok)
    expect(page.at(".simulation__summary").text.squish).to match(/Won \d of 6 \(\d+%\)/)
    expect(page.css(".simulation__runs tbody tr").size).to eq(6)
    expect(page.css(".simulation__runs tbody tr").first.text).to include("3 × Goblin")
    expect(page.css(".battle-report__side h2").map(&:text)).to include("The party, over every run", "The enemies, over every run")
    expect(page.at(".battle-report__moves").text).to include("Fire") # full tactics spend MP
    expect(page.at("#simulation_character_#{vivi.id}")[:checked]).to be_present
  end

  it "rolls each run's group from an encounter table, and plays the floor when asked" do
    table = campaign.world.encounter_tables.find_by!(slug: "grasslands")
    simulate(characters: [ cloud.id, vivi.id ], table: table.slug, runs: "12", tactics: "floor")
    against = page.css(".simulation__runs tbody tr td:last-child").map(&:text).uniq
    expect(against.size).to be > 1 # the table's groups, by weight
    expect(page.at(".battle-report__moves").text).not_to include("Fire")
    expect(page.at("#simulation_table option[selected]")["value"]).to eq(table.slug)
  end

  it "says what's missing, and is the GM's alone" do
    simulate(characters: [ cloud.id ])
    expect(page.at(".empty").text).to include("Pick who fights")

    sign_in_as(make_user("Player"))
    get campaign_simulation_path(campaign)
    expect(response).to redirect_to(root_path)
  end
end
