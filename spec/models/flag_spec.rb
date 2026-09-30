# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flag do
  let(:campaign) { create_campaign }

  it "normalises keys into identifiers, unique per campaign" do
    flag = campaign.flags.create!(key: "  Met the King! ", value: " yes ")
    expect(flag).to have_attributes(key: "met_the_king", value: "yes", label: "Met the king")
    expect(campaign.flags.new(key: "met_the_king")).not_to be_valid
    expect(campaign.flags.new(key: "42nd_street")).not_to be_valid
    expect(create_campaign(world: campaign.world, name: "Other").flags.new(key: "met_the_king")).to be_valid
  end

  it "counts whole numbers up and down, and nothing else" do
    crystals = campaign.flags.create!(key: "crystals", value: "2")
    expect(crystals).to be_counter
    crystals.bump!(1)
    crystals.bump!(-4)
    expect(crystals.reload.value).to eq("-1")

    mood = campaign.flags.create!(key: "mood", value: "grim")
    expect(mood).not_to be_counter
    expect { mood.bump!(1) }.to raise_error(Refusal, /isn't a number/)
  end
end
