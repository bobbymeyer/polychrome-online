# frozen_string_literal: true

require "rails_helper"

RSpec.describe BattleSetup do
  let(:campaign) { create_campaign }
  let!(:bartz) { create_character(campaign, name: "Bartz") }
  let!(:faris) { create_character(campaign, name: "Faris") }

  def setup(**form) = described_class.new(campaign, { characters: [ bartz.id.to_s ], encounter: { "0" => { monster: "goblin", count: "2" } } }.merge(form))

  it "reads the form's rows as one encounter: a kind twice is brought with both counts, and only the world's monsters" do
    rows = { "0" => { monster: "goblin", count: "3" }, "1" => { monster: "goblin", count: "2" }, "2" => { monster: "dragon", count: "1" } }
    expect(setup(encounter: rows).encounter).to eq("goblin" => 5)
    expect(described_class.encounter(campaign.world, { "0" => { monster: "goblin", count: "40" }, "1" => { monster: "", count: "4" } })).to eq("goblin" => 8)
    expect(described_class.encounter(campaign.world, { "0" => { monster: "goblin", count: "40" } }, most: 9)).to eq("goblin" => 9)
  end

  it "starts what it read: the ticked characters of this campaign, and the battle behind More" do
    stranger = create_character(create_campaign(world: campaign.world, name: "Elsewhere"), name: "Stranger")
    battle = setup(characters: [ "", stranger.id.to_s, faris.id.to_s ], name: "Ambush", seed: "42", escapable: "0", input_seconds: "30",
                   encounter: { "0" => { monster: "goblin", count: "1" }, "1" => { monster: "goblin", count: "1" } }).start!
    expect(battle).to have_attributes(name: "Ambush", seed: 42, input_seconds: 30, campaign: campaign)
    expect(battle.party.map(&:name)).to eq([ "Faris" ])
    expect(battle.enemies.size).to eq(2)
    expect(battle.state["escapable"]).to be(false)
    expect(campaign.messages.last.body).to eq("Ambush begins: Faris against 2 × Goblin.")
  end

  it "starts the form with nothing to face, one of a kind, so a boss picked is one boss" do
    rows = BattleSetup.defaults(campaign)[:encounter]
    expect(rows).to all(include(monster: "", count: "1"))
  end

  it "says no to a fight nobody can have" do
    bartz.update!(hp: 0)
    expect { setup.start! }.to raise_error(Refusal, /still standing/)
    expect { setup(characters: [ faris.id.to_s ], encounter: { "0" => { monster: "", count: "1" } }).start! }.to raise_error(Refusal, /at least one monster/)
    expect(campaign.battles).to be_empty
  end
end
