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
      battle.apply!({ "type" => "gm_override", "op" => "set_hp", "unit" => unit.id, "value" => 0 }, actor: "gm") unless battle.over?
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
    expect(battle.enemies.map(&:name)).to include("Morrow")
    expect(battle.boss_names).to eq([ "Morrow" ])
    expect(battle.field).not_to be_escapable # a boss fight is fought
  end

  it "makes a scene's fight a boss fight when a boss is in it: its entrance, and no fleeing it" do
    campaign.update!(current_node: barrow)
    Outcome.of("battle", target: { "name" => "The Wyrm", "monsters" => { "crystal_wyrm" => 1 } }).apply!(campaign, by: "gm")
    wyrm = campaign.current_battle
    expect(wyrm).to be_boss
    expect(wyrm.field).not_to be_escapable
    wyrm.call_off!
    Outcome.of("battle", target: { "name" => "Goblins", "monsters" => { "goblin" => 2 } }).apply!(campaign, by: "gm")
    expect(campaign.current_battle).not_to be_boss
    expect(campaign.current_battle.field).to be_escapable
  end

  it "keeps a boss waved off in its room, for when the party comes back; placing a boss sets the room waiting again" do
    walk_into_the_throne_room
    lair = barrow.location.reload
    room = campaign.pending_encounter["room"]
    campaign.wave_off_encounter!
    expect(campaign.messages.last.body).to eq("The GM holds the fight back: it waits in The Charter Vault.")
    expect(lair.reload.resolved?(room)).to be(false)

    lair.move_to!(lair.view["entrance"])
    lair.move_to!(room)
    expect(campaign.reload.pending_encounter).to include("room" => room, "boss" => true)

    # Fought through, then placed again by the GM: it waits once more.
    campaign.update!(pending_encounter: nil)
    lair.resolve!(lair.view["boss"])
    lair.place_boss!("goblin_chief" => 1)
    expect(lair.reload.resolved?(lair.view["boss"])).to be(false)
  end

  it "counts the master's room dealt with only when the fight there is won: lost, the boss waits for the party to come back" do
    walk_into_the_throne_room
    lair = barrow.location
    room = campaign.pending_encounter["room"]
    battle = campaign.start_pending_encounter!
    expect(battle.room).to eq(room)

    battle.apply!({ "type" => "gm_override", "op" => "set_hp", "unit" => battle.party.first.id, "value" => 0 }, actor: "gm")
    expect(battle.reload.status).to eq("defeat")
    expect(lair.reload.resolved?(room)).to be(false)
    expect(lair).not_to be_cleared
    expect(campaign.messages.pluck(:body)).not_to include("The Old Barrow is cleared!")

    # Back on their feet and through the door again: the boss is still there.
    campaign.recover!("get_up")
    lair.move_to!(lair.view["entrance"])
    lair.move_to!(room)
    expect(campaign.reload.pending_encounter).to include("room" => room, "boss" => true)

    win!(campaign.start_pending_encounter!)
    expect(lair.reload.resolved?(room)).to be(true)
    expect(lair).to be_cleared
    expect(campaign.messages.pluck(:body)).to include("The Old Barrow is cleared!")
  end

  it "clears nothing when the boss is sent off the field: the room waits, and so does the place" do
    walk_into_the_throne_room
    lair = barrow.location
    room = campaign.pending_encounter["room"]
    battle = campaign.start_pending_encounter!
    battle.apply!({ "type" => "gm_override", "op" => "dismiss", "unit" => morrow.battle_unit_id }, actor: "gm")
    win!(battle.reload) # the goblins he left behind
    expect(battle.reload.status).to eq("victory")
    expect(battle.result_line).to eq("Victory!") # over the goblins
    expect(battle).not_to be_bosses_beaten
    expect(lair.reload.resolved?(room)).to be(false)
    expect(lair).not_to be_cleared
    expect(campaign.messages.pluck(:body)).not_to include("The Old Barrow is cleared!")
    expect(campaign.messages.last.body).to include("Victory! Morrow got away, and will be back stronger.")
    expect(campaign.messages.last.body).not_to include("has fallen")
    expect(morrow.reload).to have_attributes(escapes: 1, location: lair) # still the Barrow's master, stronger for it
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

  it "moves in somewhere the party can find them, taking their trouble along, even to a place already cleared" do
    walk_into_the_throne_room
    win!(campaign.start_pending_encounter!)
    hollow = campaign.map_nodes.find_by!(name: "Goblin Hollow")
    den = hollow.location
    den.resolve!(den.master_room["key"]) # the party cleared it earlier, and saw off Grol Tusk for good
    campaign.npcs.find_by!(name: "Grol Tusk").update!(defeated_at: Time.current)
    expect(den).to be_cleared
    moved = { "kind" => "moved", "npc" => morrow.id, "name" => "Morrow", "from" => barrow.id, "to" => hollow.id }
    allow(Pointcrawl::Overnight).to receive(:run) { |_world, rng| [ rng, [ moved ] ] }
    campaign.update!(time_of_day: "night")
    campaign.pass_time!(1)

    expect(morrow.reload.location).to eq(den)
    expect(den.reload).not_to be_cleared
    clock = campaign.clocks.find_by!(name: "The Barrow Lord wakes")
    expect(clock.map_node).to eq(hollow)
    expect(barrow.clocks.running).to be_empty
    expect(clock.stopper).to eq("Morrow is beaten at Goblin Hollow")
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

    before = town.location.reload.service_price("inn", rook)
    campaign.place_party!(town)
    expect(campaign.messages.where(kind: "dialogue").or(campaign.messages.where(speaker: nil)).pluck(:body))
      .to include(a_string_including("“You cleared The Old Barrow? Then you've friends in #{town.name}, and friends pay less.”"))
    expect(campaign.reload.welcomes).to be_empty
    # The thanks is a deed there: the town thinks better of the party, and its prices come down.
    expect(campaign.deeds.last).to have_attributes(origin: town, sway: 2)
    expect(town.location.reload.reputation).to be >= 2
    expect(town.location.reload.service_price("inn", rook)).to be < before
  end
end
