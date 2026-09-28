# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Choices for the table" do
  let(:campaign) { create_campaign }
  let!(:bartz) { create_character(campaign, name: "Bartz") }
  let!(:lenna) { create_character(campaign, name: "Lenna") }
  let!(:cid) { campaign.npcs.create!(name: "Cid") }

  def stream(*streamables)
    Turbo::StreamsChannel.send(:stream_name_from, streamables)
  end

  it "reads “? A | B -> flag”, and nothing less" do
    expect(Message.parse_choice("? Trust Cid | Refuse -> trusted cid")).to eq(options: [ "Trust Cid", "Refuse" ], flag: "trusted cid")
    expect(Message.parse_choice("?Left|Right|Back")).to eq(options: %w[Left Right Back], flag: nil)
    expect(Message.parse_choice("? Just one")).to be_nil
    expect(Message.parse_choice("Who goes there?")).to be_nil
  end

  it "lets each character pick, and change their mind, until the GM settles it and sets the flag" do
    choice = Message.choice(campaign, options: [ "Trust Cid", "Refuse" ], flag: "trusted_cid").tap(&:save!)
    expect(choice).not_to be_dialogue
    expect(campaign.open_choice).to eq(choice)

    expect { choice.picks.create!(character: bartz, option: "Refuse") }
      .to have_broadcasted_to(stream(campaign, :table)).with(a_string_including("table_choice", "Bartz"))
    choice.picks.find_by(character: bartz).update!(option: "Trust Cid")
    choice.picks.create!(character: lenna, option: "Trust Cid")
    expect(choice.tally).to eq("Trust Cid" => %w[Bartz Lenna], "Refuse" => [])
    expect { choice.picks.create!(character: lenna, option: "Refuse") }.to raise_error(ActiveRecord::RecordInvalid)

    choice.settle!("Trust Cid")
    expect(campaign.flags.find_by!(key: "trusted_cid")).to have_attributes(value: "Trust Cid", public: true)
    expect(campaign.messages.last.body).to eq("The party chose: Trust Cid.")
    expect(campaign.open_choice).to be_nil
    expect { choice.picks.find_by(character: bartz).update!(option: "Refuse") }.to raise_error(ActiveRecord::RecordInvalid)
    expect { choice.settle!("Refuse") }.to raise_error(Refusal, /settled already/)
  end

  it "can end a scene, and only end it" do
    scene = campaign.scenes.new(name: "Crossroads", script: "Cid: Well?\n? Trust Cid | Refuse -> trusted_cid")
    expect(scene).to be_valid
    expect(scene.summary).to eq("1 line, then a choice: Trust Cid / Refuse")
    scene.save!
    scene.play!
    expect(campaign.messages.chronological.map(&:kind)).to eq(%w[say choice])
    expect(campaign.open_choice.flag_key).to eq("trusted_cid")

    expect(campaign.scenes.new(name: "Bad", script: "? A | B\nCid: after")).not_to be_valid
    expect(campaign.scenes.new(name: "Bad", script: "? A | B", ending: "battle", encounter: { "goblin" => 1 })).not_to be_valid
    expect(campaign.scenes.new(name: "Bad", script: "? Only one").tap(&:valid?).errors[:script].join).to include("two options")
  end
end
