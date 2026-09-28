# frozen_string_literal: true

require "rails_helper"

RSpec.describe Seat do
  let(:campaign) { create_campaign }
  let(:bartz) { create_character(campaign, name: "Bartz") }
  let(:lenna) { create_character(campaign, name: "Lenna") }

  def line(**attrs) = campaign.messages.create!(body: "Hello.", **attrs)

  it "listens on the table, its audience's copy, and its own whispers" do
    expect(described_class.gm.streams(campaign)).to eq([ [ campaign, :table ], [ campaign, :gm ] ])
    expect(described_class.of(bartz).streams(campaign)).to eq([ [ campaign, :table ], [ campaign, :players ], [ bartz, :whispers ] ])
    expect(described_class.nobody.streams(campaign)).to eq([ [ campaign, :table ], [ campaign, :players ] ])
  end

  it "lets the GM take back any line said, a player only their own, and nobody what the game logged" do
    narration = line
    said = line(speaker: bartz)
    logged = line(kind: "system")
    expect(described_class.gm.may_retract?(narration)).to be(true)
    expect(described_class.of(bartz).may_retract?(said)).to be(true)
    expect(described_class.of(lenna).may_retract?(said)).to be(false)
    expect(described_class.nobody.may_retract?(narration)).to be(false) # no speaker is not "the same speaker"
    expect(described_class.gm.may_retract?(logged)).to be(false)
    expect([ described_class.gm, described_class.of(bartz), described_class.nobody ].map(&:retracts)).to eq([ "all", "Character:#{bartz.id}", nil ])
  end

  it "is a battle unit's, with or without a character behind it" do
    expect(described_class.of(bartz)).to have_attributes(unit_id: bartz.battle_unit_id, name: "Bartz", seated?: true)
    expect(described_class.of(nil, unit_id: "guest_1")).to have_attributes(character?: false, seated?: true)
    expect(described_class.nobody).not_to be_seated
  end
end
