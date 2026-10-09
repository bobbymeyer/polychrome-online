# frozen_string_literal: true

require "rails_helper"

# A Thief's work in a dungeon (docs/ODA.md): traps that wait in a room, a
# lock opened without its key, and getting caught at it in town.
RSpec.describe "Traps, picked locks and getting caught" do
  let(:world) { base_world }
  let(:campaign) { base_campaign }
  let(:cave) { world.location_templates.find_by!(slug: "goblin_cave") }
  let(:dungeon) do
    campaign.locations.create!(location_template: cave, seed: 11).tap do |d|
      campaign.update!(current_node: campaign.map_nodes.create!(name: "Cave", kind: "dungeon", x: 1, y: 1, location: d))
    end
  end
  let(:entrance) { dungeon.view["entrance"] }
  let!(:bartz) { create_character(campaign, name: "Bartz") }

  def trapped(text = "A tripwire and a powder charge. (hurt 20)")
    dungeon.enter!
    key = dungeon.add_room!(name: "Gallery", connect: entrance, decision: { "kind" => "trap", "text" => text })
    beyond = dungeon.add_room!(name: "Beyond", connect: key, decision: { "kind" => "event", "text" => "Quiet." })
    dungeon.move_to!(key)
    [ key, beyond ]
  end

  it "waits in its room, said at the table, until someone deals with it" do
    key, = trapped
    expect(dungeon.trap_waiting?(key)).to be(true)
    expect(campaign.messages.last.body).to eq("A trap in Gallery: A tripwire and a powder charge. Disarm it, or it goes off when the party moves on.")
  end

  it "goes off when let go, or walked past, doing what its brackets say" do
    key, beyond = trapped
    before = bartz.reload.current_hp
    dungeon.move_to!(beyond)
    expect(dungeon.reload.resolved?(key)).to be(true)
    expect(bartz.reload.current_hp).to be < before
    expect(campaign.messages.pluck(:body)).to include("The trap goes off!")
  end

  it "is disarmed on a successful check, and goes off on a failed one" do
    key, = trapped
    allow(campaign).to receive(:check!).and_wrap_original do |original, **args|
      original.call(**args, difficulty: "easy")
    end
    outcomes = 20.times.map do
      dungeon.update!(progress: dungeon.progress.merge("resolved" => dungeon.progress.fetch("resolved", []) - [ key ]))
      dungeon.disarm_trap!(key, character: bartz, stat: "agi")
      campaign.messages.order(:id).last(2).map(&:body).join(" ")
    end
    expect(outcomes.join).to include("disarms it")
    expect(dungeon.reload.resolved?(key)).to be(true)
  end

  describe "a lock in the way" do
    let(:lock_path) { dungeon.view["paths"].find { |p| p["lock"] } }

    before do
      near = lock_path["from"]
      dungeon.update!(progress: { "current" => near, "visited" => [ near ], "resolved" => [ near ] })
    end

    it "opens to a picked lock (the unlock outcome), key or no key" do
      expect(dungeon.locks_in_the_way.map { |l| l["id"] }).to eq([ lock_path["lock"]["id"] ])
      line = Outcome.of("unlock").apply!(campaign, by: "Rook")
      expect(line).to include("Rook works at #{lock_path['lock']['name']}")
      expect(dungeon.reload.unlocked?(lock_path["lock"])).to be(true)
      expect(dungeon.locks_in_the_way).to be_empty
      dungeon.move_to!(lock_path["to"])
      expect(dungeon.reload.current_room_key).to eq(lock_path["to"])
    end

    it "is something a field ability can do, and a check can't when there's no lock" do
      expect(FieldUse::OUTCOMES).to include("unlock")
      expect(Outcome::ON_A_CHECK).to include("unlock")
      dungeon.update!(progress: dungeon.progress.merge("unlocked" => [ lock_path["lock"]["id"] ]))
      expect { Outcome.of("unlock").can_happen!(campaign) }.to raise_error(Refusal, /no lock/)
    end
  end

  it "rolls traps from a template that weighs them, and only then" do
    template = { "rooms" => [ 8, 8 ], "decisions" => { "trap" => 5, "event" => 1 } }
    tables = { "traps" => [ { "text" => "A pit. (hurt 10)" } ], "room_events" => [ { "text" => "Dust." } ] }
    dungeon = Generators::Dungeon.generate(seed: 3, template: template, encounters: [], tables: tables)
    expect(dungeon["rooms"].map { |r| r.dig("decision", "kind") }).to include("trap")
    expect(dungeon["rooms"].find { |r| r.dig("decision", "kind") == "trap" }["decision"]["text"]).to eq("A pit. (hurt 10)")
    plain = Generators::Dungeon.generate(seed: 3, template: template, encounters: [], tables: tables.except("traps"))
    expect(plain["rooms"].map { |r| r.dig("decision", "kind") }).not_to include("trap")
  end

  describe "caught in town" do
    let(:town) { campaign.map_nodes.create!(name: "Noonbell", kind: "town", x: 5, y: 5) }

    before { campaign.update!(current_node: town) }

    it "costs the party the town's good opinion when everyone fails a check that says so" do
      allow(Stats::Check).to receive(:roll).and_wrap_original { |original, **args| original.call(**args).merge("success" => false) }
      campaign.check!(characters: [ bartz ], stat: "agi", difficulty: "hard", reason: "lift a purse", failure: Outcome.of("disgrace"))
      deed = campaign.deeds.last
      expect(deed.sway).to eq(-1)
      expect(campaign.messages.pluck(:body)).to include("Noonbell saw that. They'll remember it.")
    end

    it "costs nothing more when someone succeeds" do
      allow(Stats::Check).to receive(:roll).and_wrap_original { |original, **args| original.call(**args).merge("success" => true) }
      campaign.check!(characters: [ bartz ], stat: "agi", difficulty: "hard", failure: Outcome.of("disgrace"))
      expect(campaign.deeds).to be_empty
    end
  end
end
