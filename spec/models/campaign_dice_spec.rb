# frozen_string_literal: true

require "rails_helper"

RSpec.describe "A campaign's dice" do
  let(:campaign) { create_campaign }

  it "keeps where the dice got to, so the next roll is a new one" do
    first = campaign.roll { |dice| Array.new(5) { dice.int(1000) } }
    second = campaign.reload.roll { |dice| Array.new(5) { dice.int(1000) } }
    expect(second).not_to eq(first)
  end

  it "rolls the same from the same state, however the roll is made" do
    state = campaign.rng
    by_dice = campaign.roll { |dice| dice.int(1000) }
    campaign.update!(rng: state)
    by_state = campaign.roll_with { |s| (dice = Battle::Rng.new(s)).int(1000).then { |n| [ dice.state, n ] } }
    expect(by_state).to eq(by_dice)
    expect(campaign.reload.rng).not_to eq(state)
  end
end
