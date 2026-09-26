# frozen_string_literal: true

# Property-style specs (§5): hundreds of chaotic, seeded battles, with
# invariants checked after every single action.
RSpec.describe "Battle resolver properties" do
  def tables
    RandomTable.played(1..250)
  end

  def each_step
    tables.each do |table|
      table.steps.each { |before, action, after, events| yield table, before, action, after, events }
    end
  end

  it "actually exercises the engine" do
    all_events = tables.flat_map { |t| t.steps.flat_map(&:last) }
    seen = all_events.map { |e| e["type"] }.uniq
    expect(seen).to include(*%w[attack cast damage miss crit heal status_applied status_expired ko revive
                                  turn_start turn_end flee victory defeat gm_override buff_applied
                                  buff_expired turn_skipped timeout])
    expect(tables.filter_map { |t| t.steps.last&.at(2)&.fetch("status") }.uniq).to include("victory", "defeat")
  end

  it "keeps HP and MP within bounds, as integers" do
    each_step do |_, _, _, after, _|
      after["units"].each do |u|
        expect(u["hp"]).to be_a(Integer).and(be_between(0, u["stats"]["max_hp"]))
        expect(u["mp"]).to be_a(Integer).and(be_between(0, u["stats"]["max_mp"]))
      end
    end
  end

  it "never reports negative or non-integer amounts" do
    each_step do |_, _, _, _, events|
      events.select { |e| e.key?("amount") && e["type"] != "buff_applied" && e["type"] != "buff_expired" }.each do |e|
        expect(e["amount"]).to be_a(Integer).and(be >= 0)
      end
      events.select { |e| e.key?("hp") }.each { |e| expect(e["hp"]).to be >= 0 }
    end
  end

  it "never lets a KO'd unit act or be damaged" do
    each_step do |_, before, _, _, events|
      down = before["units"].reject { |u| u["hp"].positive? }.map { |u| u["id"] }
      events.each do |e|
        case e["type"]
        when "ko" then down << e["target"]
        when "revive" then down.delete(e["target"])
        when "turn_start" then expect(down).not_to include(e["unit"])
        when "attack", "cast", "defend" then expect(down).not_to include(e["actor"])
        when "damage", "heal", "status_applied", "buff_applied" then expect(down).not_to include(e["target"])
        end
      end
    end
  end

  it "leaves KO'd units without statuses or buffs" do
    each_step do |_, _, _, after, _|
      after["units"].reject { |u| u["hp"].positive? }.each do |u|
        expect(u["statuses"]).to be_empty
        expect(u["buffs"]).to be_empty
      end
    end
  end

  it "keeps status and buff durations positive" do
    each_step do |_, _, _, after, _|
      after["units"].each do |u|
        (u["statuses"] + u["buffs"]).each { |s| expect(s["turns"]).to be > 0 }
        expect(u["statuses"].map { |s| s["kind"] }).to eq(u["statuses"].map { |s| s["kind"] }.uniq)
      end
    end
  end

  it "gives each unit at most one turn per round" do
    each_step do |_, _, _, _, events|
      events.slice_before { |e| e["type"] == "round_start" }.each do |round|
        starts = of_type(round, :turn_start).map { |e| e["unit"] }
        expect(starts).to eq(starts.uniq)
      end
    end
  end

  it "keeps turn_start/turn_end balanced" do
    each_step do |_, _, _, _, events|
      expect(of_type(events, :turn_start).size).to eq(of_type(events, :turn_end).size)
    end
  end

  it "only advances the round by whole rounds" do
    each_step do |_, before, _, after, events|
      ran = of_type(events, :round_end).any?
      expected = ran && after["status"] == "input" ? before["round"] + 1 : before["round"]
      expect(after["round"]).to eq(expected)
    end
  end

  it "emits exactly one terminal event when a battle ends" do
    each_step do |_, before, _, after, events|
      terminal = events.count { |e| %w[victory defeat].include?(e["type"]) || (e["type"] == "flee" && e["success"]) }
      expect(terminal).to eq(before["status"] == after["status"] ? 0 : 1)
    end
  end

  it "keeps every state JSON-stable and the RNG within 32 bits" do
    each_step do |_, _, _, after, _|
      expect(JSON.parse(JSON.generate(after))).to eq(after)
      expect(after["rng"]).to be_between(0, 0xFFFF_FFFF)
    end
  end

  it "never touches RNG while collecting input" do
    each_step do |_, before, _, after, events|
      next if of_type(events, :round_start).any?

      expect(after["rng"]).to eq(before["rng"])
    end
  end

  it "replays every battle exactly from its initial state and action log" do
    tables.each do |table|
      next if table.steps.empty?

      final, events = Battle::Replay.run(table.initial, table.actions)
      expect(final).to eq(table.steps.last[2])
      expect(events.map { |e| e.except("step") }).to eq(table.steps.flat_map(&:last))
    end
  end

  it "resumes identically from any persisted mid-battle state" do
    tables.first(50).each do |table|
      table.steps.each_with_index do |(before, action, after, events), i|
        next unless (i % 7).zero?

        reloaded = JSON.parse(JSON.generate(before))
        expect(Battle::Resolver.apply(reloaded, action)).to eq([ after, events ])
      end
    end
  end
end
