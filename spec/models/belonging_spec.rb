# frozen_string_literal: true

require "rails_helper"

RSpec.describe Campaign::Belonging do
  let(:world) { base_world }
  let(:campaign) { base_campaign }
  let(:village) { world.location_templates.find_by!(slug: "village") }
  let(:crossing) { campaign.map_nodes.create!(name: "Crossing", kind: "field", x: 1, y: 1, visible: true) }
  let(:hollin) do
    campaign.map_nodes.create!(name: "Hollin", kind: "town", x: 5, y: 5, location: campaign.locations.create!(location_template: village, seed: 3))
  end
  let(:road) { campaign.map_edges.create!(from_node: crossing, to_node: hollin) }
  let(:mara) { campaign.npcs.create!(name: "Mara Vell", location: hollin.location) }
  let!(:vivi) { create_character(campaign, name: "Vivi", home_node: hollin) }
  let!(:bartz) { create_character(campaign, name: "Bartz") }

  before { campaign.update!(current_node: crossing) }

  def whispers_to(character)
    campaign.messages.where(scope: "whisper", recipient: character).pluck(:body)
  end

  it "says who is home when the party arrives there" do
    campaign.travel!(road)
    expect(campaign.messages.pluck(:body)).to include("Vivi is home.")
    campaign.place_party!(crossing)
    expect(campaign.messages.pluck(:body)).not_to include(a_string_matching(/Bartz.*home/))
  end

  it "whispers a tie when the tied NPC lives where the party arrives, once a session" do
    bartz.update!(ties: [ { "npc_id" => mara.id, "text" => "Owes her money." } ])
    campaign.travel!(road)
    expect(whispers_to(bartz)).to eq([ "Your tie to Mara Vell: Owes her money." ])
    expect(whispers_to(vivi)).to be_empty

    campaign.messages.create!(body: "Back so soon?", speaker: mara)
    expect(whispers_to(bartz).size).to eq(1)
  end

  it "whispers a tie when the tied NPC first speaks, wherever they are" do
    bartz.update!(ties: [ { "npc_id" => mara.id, "text" => "Owes her money." } ])
    campaign.messages.create!(body: "You again.", speaker: mara)
    expect(whispers_to(bartz)).to eq([ "Your tie to Mara Vell: Owes her money." ])
    expect(Message.visible_to(campaign, Seat.of(vivi)).map(&:body)).not_to include(a_string_starting_with("Your tie"))
    expect(Message.visible_to(campaign, Seat.gm).map(&:body)).to include(a_string_starting_with("Your tie"))

    travel_to(4.hours.from_now) do
      campaign.messages.create!(body: "Well?", speaker: mara)
      expect(whispers_to(bartz).size).to eq(2)
    end
  end
end
