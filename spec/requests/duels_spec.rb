# frozen_string_literal: true

require "rails_helper"

# A duel from the table's challenge to its swings (docs/ODA.md).
RSpec.describe "Duels at the table", type: :request do
  let(:campaign) { create_campaign.tap { |c| c.update!(gm: @admin) } }
  let(:krile) { make_user("Krile") }
  let!(:bartz) { create_character(campaign, name: "Bartz", user: krile) }
  let!(:ronin) { create_monster(campaign.world, slug: "ronin") }

  def challenge(by: "opponent")
    sit(campaign, "gm")
    post campaign_challenge_path(campaign), params: { character_id: bartz.id, monster: "ronin", line: "Draw.", by: by }
  end

  it "puts the challenge to the challenged player, who accepts and swings their own meter" do
    challenge
    at_the_table(campaign, as: "gm")
    expect(page.at_css("#table_now").text).to include("Ronin challenges Bartz to a duel!", "Draw.")

    sign_in_as(krile)
    at_the_table(campaign, as: bartz)
    expect(page.at_css("#table_now").text).to include("Accept", "Refuse")
    post campaign_challenge_answer_path(campaign), params: { answer: "accept" }
    duel = campaign.reload.current_duel
    expect(duel).to be_on

    get campaign_table_path(campaign)
    meters = page.css(".duel-meter")
    expect(meters.size).to eq(2)
    expect(page.css(".duel-meter__swing").size).to eq(1) # only their own
    expect(page.css("[data-controller=duel-meter] .duel-meter__name").text).to eq("Bartz")

    post campaign_duel_swings_path(campaign, duel), params: { side: "character", position: duel.zone["center"] }
    expect(duel.reload.swung?("character")).to be(true)
    post campaign_duel_swings_path(campaign, duel), params: { side: "gm", position: 10 }
    expect(duel.reload.swung?("gm")).to be(false) # the GM's swing isn't theirs
  end

  it "lets the GM swing the opponent's meter, and put the result away" do
    challenge(by: "character")
    duel = campaign.reload.current_duel
    get campaign_table_path(campaign)
    expect(page.css("[data-controller=duel-meter] .duel-meter__name").text).to eq("Ronin")
    3.times do
      duel.reload.swing!("character", duel.zone["center"])
      post campaign_duel_swings_path(campaign, duel), params: { side: "gm", position: duel.reload.zone["center"] }
    end
    expect(duel.reload).to be_over
    get campaign_table_path(campaign)
    expect(page.at_css(".duel__result").text).to eq("SATISFACTION")
    patch campaign_duel_path(campaign, duel)
    expect(campaign.reload.current_duel).to be_nil
  end

  it "makes a coward of a player who refuses" do
    challenge
    sign_in_as(krile)
    sit(campaign, bartz)
    post campaign_challenge_answer_path(campaign), params: { answer: "refuse" }
    expect(bartz.reload).to be_coward
    get character_path(bartz)
    expect(response.body).to include("A coward.")
  end

  it "lets only the challenged character, or the GM, answer" do
    challenge
    stranger = make_user("Stranger")
    create_character(campaign, name: "Faris", user: stranger)
    sign_in_as(stranger)
    sit(campaign, campaign.characters.find_by!(name: "Faris"))
    post campaign_challenge_answer_path(campaign), params: { answer: "refuse" }
    expect(bartz.reload).not_to be_coward
    expect(campaign.reload.challenge).to be_present
  end

  it "offers the GM a duel under the Fight control" do
    sit(campaign, "gm")
    patch campaign_controls_path(campaign), params: { kind: "battle" }
    get campaign_table_path(campaign)
    expect(page.at_css(".duel-setup").text).to include("A duel", "They challenge")
  end

  it "keeps challenges for the GM" do
    sign_in_as(krile)
    sit(campaign, bartz)
    post campaign_challenge_path(campaign), params: { character_id: bartz.id, monster: "ronin" }
    expect(campaign.reload.challenge).to be_nil
  end
end
