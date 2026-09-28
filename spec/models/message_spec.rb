# frozen_string_literal: true

require "rails_helper"

RSpec.describe Message do
  let(:campaign) { create_campaign }
  let(:bartz) { create_character(campaign, name: "Bartz") }
  let(:lenna) { create_character(campaign, name: "Lenna") }
  let(:cid) { campaign.npcs.create!(name: "Cid", title: "Engineer") }

  def say(**attrs)
    campaign.messages.create!({ body: "Hello." }.merge(attrs))
  end

  describe "who speaks and how it's shown (§9.5)" do
    it "plays GM narration and NPC lines in the dialogue box" do
      expect(say).to be_dialogue
      expect(say(speaker: cid, expression: "angry")).to be_dialogue
    end

    it "sends player lines, whispers and system lines to the log only" do
      expect(say(speaker: bartz)).not_to be_dialogue
      expect(say(speaker: cid, scope: "whisper", recipient: bartz)).not_to be_dialogue
      expect(say(kind: "system")).not_to be_dialogue
    end

    it "names the narrator" do
      expect(say.speaker_name).to eq("Narrator")
    end
  end

  describe "validation" do
    it "needs a body and a known expression" do
      expect(campaign.messages.new(body: "  ")).not_to be_valid
      expect(campaign.messages.new(body: "Hi", expression: "smug")).not_to be_valid
      expect(campaign.messages.new(body: "Hi", expression: "")).to be_valid
    end

    it "keeps everyone at the same table" do
      stranger = create_character(create_campaign(world: campaign.world, name: "Elsewhere"), name: "Stranger")
      message = campaign.messages.new(body: "Hi", speaker: stranger)
      expect(message).not_to be_valid
      expect(message.errors[:speaker]).to include(/campaign/)
    end

    it "gives whispers two ends: player to GM, or GM to a player" do
      expect(campaign.messages.new(body: "Psst", scope: "whisper", speaker: bartz)).to be_valid
      expect(campaign.messages.new(body: "Psst", scope: "whisper", speaker: bartz, recipient: lenna)).not_to be_valid
      expect(campaign.messages.new(body: "Psst", scope: "whisper", speaker: cid, recipient: bartz)).to be_valid
      expect(campaign.messages.new(body: "Psst", scope: "whisper")).not_to be_valid
      expect(campaign.messages.new(body: "Hi", recipient: bartz)).not_to be_valid
    end
  end

  describe "visibility" do
    let!(:table_line) { say(speaker: cid) }
    let!(:to_bartz) { say(scope: "whisper", recipient: bartz) }
    let!(:from_lenna) { say(scope: "whisper", speaker: lenna) }

    it "shows whispers only to the GM and the character involved" do
      expect(described_class.visible_to(campaign, Seat.gm)).to eq([ table_line, to_bartz, from_lenna ])
      expect(described_class.visible_to(campaign, Seat.of(bartz))).to eq([ table_line, to_bartz ])
      expect(described_class.visible_to(campaign, Seat.of(lenna))).to eq([ table_line, from_lenna ])
      expect(described_class.visible_to(campaign, Seat.nobody)).to eq([ table_line ])
    end

    it "agrees with Seat#sees?" do
      [ Seat.gm, Seat.of(bartz), Seat.of(lenna), Seat.nobody ].each do |seat|
        visible = described_class.visible_to(campaign, seat)
        [ table_line, to_bartz, from_lenna ].each do |message|
          expect(seat.sees?(message)).to eq(visible.include?(message)), "#{seat.name.inspect} / #{message.body}"
        end
      end
    end
  end

  describe "broadcasts (scoped, §7)" do
    it "sends table lines to the table stream" do
      expect { say(speaker: cid) }.to have_broadcasted_to(stream(campaign, :table)).with(a_string_including("Hello."))
    end

    it "sends whispers only to the GM and that character, never the table" do
      expect { say(scope: "whisper", recipient: bartz, body: "Secret") }
        .to have_broadcasted_to(stream(campaign, :gm)).with(a_string_including("Secret"))
        .and have_broadcasted_to(stream(bartz, :whispers)).with(a_string_including("Secret"))
        .and have_broadcasted_to(stream(campaign, :table)).exactly(0).times
      expect { say(scope: "whisper", speaker: lenna, body: "Other") }.to have_broadcasted_to(stream(bartz, :whispers)).exactly(0).times
    end
  end
end
