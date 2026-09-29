# frozen_string_literal: true

require "rails_helper"

# The setting's villains meet the party in their own lair, get away the first
# time, and clearing a place changes the world around it.
RSpec.describe "Villains and what clearing a place changes" do
  let(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "The Barrow Road").tap { |c| c.set_out! } }
  let(:barrow) { campaign.map_nodes.find_by!(name: "The Old Barrow") }
  let(:morrow) { campaign.npcs.find_by!(name: "Morrow") }
  let!(:rook) { create_character(campaign, name: "Rook") }

  def win!(battle)
    battle.enemies.each do |unit|
      battle.apply!({ "type" => "gm_override", "op" => "set_hp", "unit" => unit["id"], "value" => 0 }, actor: "gm") unless battle.over?
    end
  end

  def walk_into_the_throne_room
    campaign.update!(current_node: barrow)
    lair = barrow.location
    lair.enter!
    key = lair.add_room!(name: "The Charter Vault", connect: lair.view["entrance"], decision: { "kind" => "boss", "monsters" => { "goblin_chief" => 1, "goblin" => 2 } })
    lair.move_to!(key)
    campaign.reload
  end

  it "puts the villain at the head of their own boss room, with their own entrance" do
    walk_into_the_throne_room
    waiting = campaign.pending_encounter
    expect(waiting).to include("antagonists" => [ morrow.id ], "monsters" => { "goblin" => 2 }, "boss" => true)
    expect(waiting["prelude"]).to include("Morrow, the Barrow Lord, turns to face you.", "Tule's reeve, a hundred years dead, and not finished.")
    expect(campaign.messages.last.body).to eq("Boss! Morrow, The Barrow Lord, with 2 × Goblin.")

    battle = campaign.start_pending_encounter!
    expect(battle.enemies.map { |u| u["name"] }).to include("Morrow")
    expect(battle.boss_names).to eq([ "Morrow" ])
  end

  it "lets the villain slip away the first time, their trouble still running; the second time, down is down" do
    walk_into_the_throne_room
    win!(campaign.start_pending_encounter!)

    expect(morrow.reload).to have_attributes(escapes: 1, defeated_at: nil)
    expect(campaign.messages.pluck(:body)).to include(a_string_including("Morrow falls, and when the dust settles is gone. This isn't over."),
                                                      "The Old Barrow is cleared!")
    expect(barrow.clocks.running).to be_present # the Barrow Lord still wakes

    again = BattleRecord.start!(campaign: campaign, characters: [ rook ], name: "Morrow, again", encounter: {}, antagonists: [ morrow ])
    win!(again)
    expect(morrow.reload).to be_defeated
  end

  it "quietens the roads out of a cleared place, brings its secrets out, and has the nearest town welcome the party back" do
    wilds = campaign.map_nodes.create!(name: "Bone Road", kind: "wilds", x: 5, y: 5, visible: true)
    road = campaign.map_edges.create!(from_node: barrow, to_node: wilds, state: "dangerous")
    walk_into_the_throne_room
    win!(campaign.start_pending_encounter!)

    expect(road.reload.state).to eq("open")
    expect(campaign.messages.pluck(:body)).to include("The roads out of The Old Barrow are quiet now.",
                                                      a_string_including("In The Old Barrow: the party learns: Morrow was Tule's reeve"))
    town = campaign.nearest_town(barrow)
    expect(campaign.reload.welcomes).to eq(town.id.to_s => "The Old Barrow")

    campaign.place_party!(town)
    expect(campaign.messages.where(kind: "dialogue").or(campaign.messages.where(speaker: nil)).pluck(:body))
      .to include(a_string_including("“You cleared The Old Barrow? Then your rooms are on the house while you're here.”"))
    expect(campaign.reload.welcomes).to be_empty
    expect(campaign.service_price("inn", rook)).to eq(0)

    campaign.place_party!(barrow)
    expect(campaign.reload.service_price("inn", rook)).to be_positive
  end
end
