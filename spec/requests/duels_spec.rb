# frozen_string_literal: true

require "rails_helper"

# A duel from the table to the last exchange (docs/ODA.md).
RSpec.describe "Duels at the table", type: :request do
  let(:campaign) { create_campaign.tap { |c| c.update!(gm: @admin) } }
  let(:krile) { make_user("Krile") }
  let!(:bartz) { create_character(campaign, name: "Bartz", user: krile) }
  let!(:ronin) { create_monster(campaign.world, slug: "ronin", tells: { "strike" => [ "Now." ] }) }

  def challenge(by: "opponent")
    sit(campaign, "gm")
    post campaign_challenge_path(campaign), params: { character_id: bartz.id, monster: "ronin", line: "Draw.", by: by }
  end

  it "puts the challenge to the challenged player, who accepts and duels in stances" do
    challenge
    expect(campaign.reload.challenge).to include("character_id" => bartz.id, "monster" => "ronin")
    at_the_table(campaign, as: "gm")
    expect(page.at_css("#table_now").text).to include("Ronin challenges Bartz to a duel!", "Draw.")

    sign_in_as(krile)
    at_the_table(campaign, as: bartz)
    expect(page.at_css("#table_now").text).to include("Accept", "Refuse")
    post campaign_challenge_answer_path(campaign), params: { answer: "accept" }
    battle = campaign.reload.current_battle
    expect(battle).to be_duel
    expect(response).to redirect_to(battle_path(battle))

    sit_in_battle(battle, bartz.battle_unit_id)
    get battle_panel_path(battle)
    expect(page.css(".pick-row__act").map(&:text)).to eq(%w[Strike Guard Feint])
    expect(page.at_css(".duel-tell")).to be_present
    expect(response.body).not_to include(battle.state["duel"]["planned"].capitalize + " is coming")

    post battle_actions_path(battle), params: { command: { kind: "stance", stance: "guard" } }
    events = battle.reload.battle_events.map(&:kind)
    expect(events).to include("stare", "reveal", "clash")
    expect(battle.state["duel"]["exchange"]).to eq(2)
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

  it "starts a character's own challenge at once" do
    challenge(by: "character")
    battle = campaign.reload.current_battle
    expect(battle).to be_duel
    expect(campaign.challenge).to be_nil
  end

  it "offers the GM a duel under the Fight control, and shows the duel's board" do
    sit(campaign, "gm")
    patch campaign_controls_path(campaign), params: { kind: "battle" }
    get campaign_table_path(campaign)
    expect(page.at_css(".duel-setup").text).to include("A duel", "They challenge")
    challenge(by: "character")
    battle = campaign.reload.current_battle
    get battle_path(battle)
    expect(response).to have_http_status(:ok)
    sit_in_battle(battle, "gm")
    get battle_panel_path(battle)
    expect(response).to have_http_status(:ok)
  end

  it "keeps challenges for the GM" do
    sign_in_as(krile)
    sit(campaign, bartz)
    post campaign_challenge_path(campaign), params: { character_id: bartz.id, monster: "ronin" }
    expect(campaign.reload.challenge).to be_nil
  end
end
