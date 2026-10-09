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
                                  buff_expired turn_skipped timeout desperation unit_joined unit_left custom_action custom_roll
                                  jump land away back covered counter second_wind mp_restored
                                  shielded confused mp_lost hp_paid charging summoned one_more all_out
                                  gathered patience reflected iai quick mimic transformed unmasked reraise])
    expect(tables.filter_map { |t| t.steps.last&.at(2)&.fetch("status") }.uniq).to include("victory", "defeat")
    expect(all_events.map { |e| e["type"] }).to include("item_used")
  end

  it "lets each character's desperation move out at most once a battle, only from an attack at a quarter HP or less, at no cost" do
    tables.each do |table|
      moves = table.steps.flat_map { |_, _, _, events| events.select { |e| e["type"] == "desperation" } }
      expect(moves.map { |e| e["actor"] }).to eq(moves.map { |e| e["actor"] }.uniq)
    end
    each_step do |_, before, action, after, events|
      events.each_with_index do |event, i|
        next unless event["type"] == "desperation"

        unit = after["units"].find { |u| u["id"] == event["actor"] }
        expect(unit["desperation_used"]).to be(true)
        expect(event["ability"]).to eq(unit["desperation"])
        announced = events[(i + 1)..].find { |e| %w[attack cast action_failed].include?(e["type"]) && e["actor"] == event["actor"] }
        expect(announced).to include("ability" => event["ability"]) if announced
        expect(announced["mp_cost"]).to eq(0) if announced&.key?("mp_cost")
        expect(before["inputs"].dig(event["actor"], "ability") || "attack").to eq("attack")
      end
    end
  end

  it "keeps units that left out of play, guests off the input list, and new arrivals uniquely named" do
    each_step do |_, before, _, after, events|
      gone = before["units"].select { |u| u["gone"] }.map { |u| u["id"] }
      events.each do |e|
        expect(gone).not_to include(e["actor"], e["target"], e["unit"]) unless e["type"] == "gm_override"
      end
      expect(Battle::State.awaiting_input(after) & after["units"].select { |u| u["guest"] || u["gone"] }.map { |u| u["id"] }).to be_empty
      expect(after["units"].map { |u| u["id"] }).to eq(after["units"].map { |u| u["id"] }.uniq)
      expect(gone - after["units"].select { |u| u["gone"] }.map { |u| u["id"] }).to be_empty
    end
  end

  it "never pays out for an enemy that left" do
    each_step do |_, _, _, after, events|
      victory = events.find { |e| e["type"] == "victory" }
      next unless victory

      earned = after["units"].select { |u| u["side"] == "enemy" && !u["gone"] }.sum { |u| u.dig("rewards", "exp").to_i }
      expect(victory.dig("rewards", "exp").to_i).to eq(earned)
    end
  end

  it "shows honest dice: every roll is 1–100, and came in exactly when it's at or over what was needed (high is good)" do
    seen = 0
    each_step do |_, _, _, _, events|
      events.select { |e| e.key?("roll") }.each do |e|
        seen += 1
        expect(e["roll"]).to be_between(1, 100)
        came_in = e["roll"] >= e["needed"]
        case e["type"]
        when "crit", "steal", "status_applied" then expect(came_in).to be(true)
        when "miss" then expect(came_in).to be(false)
        when "flee" then expect(came_in).to eq(e["success"])
        when "custom_roll" then expect(e["success"]).to eq(e["roll"] >= 96 || (e["roll"] > 5 && e["total"] >= e["needed"])) # the die, then the modifiers
        when "counter" then expect(came_in).to be(true)
        end
      end
    end
    expect(seen).to be_positive
  end

  it "never runs a round past an idea the GM hasn't ruled on, unless the timer or the GM forces it" do
    each_step do |_, before, action, _, events|
      next unless of_type(events, :round_start).any?
      next if %w[timeout].include?(action["type"]) || action["op"] == "execute_round"

      pending = before["inputs"].select { |_, c| c["kind"] == "custom" && !c["ruling"] }.keys
      pending -= [ action["unit"] ] if action["op"] == "rule"
      expect(pending).to be_empty
    end
  end

  it "keeps a unit that's away out of reach and out of the input, until it comes back" do
    gone = ->(u) { u["statuses"].any? { |s| Battle::OUT_OF_REACH_STATUSES.include?(s["kind"]) } }
    each_step do |_, before, _, after, events|
      away = before["units"].select(&gone).map { |u| u["id"] }
      side = (before["units"] + after["units"]).to_h { |u| [ u["id"], u["side"] ] }
      reach = false
      events.each do |e|
        case e["type"]
        when "attack", "cast" then reach = before["abilities"].dig(e["ability"], "reach")
        when "turn_start" then reach = false
        when "jump" then away << e["actor"]
        when "away" then away << e["unit"]
        when "land" then away.delete(e["actor"])
        when "back" then away.delete(e["unit"])
        when "ko" then away.delete(e["target"])
        when "damage", "miss"
          # Out of the enemy's reach (an ally can still hand them a potion).
          # (A move with reach can find them: a Ranger's shot.)
          expect(away).not_to include(e["target"]) if e["actor"] && side[e["actor"]] != side[e["target"]] && e["reason"] != "no_target" && !reach
        end
      end
      expect(Battle::State.awaiting_input(after) & after["units"].select(&gone).map { |u| u["id"] }).to be_empty
    end
  end

  it "lets a Second Wind happen once a battle" do
    tables.each do |table|
      winds = table.steps.flat_map { |_, _, _, events| events.select { |e| e["type"] == "second_wind" }.map { |e| e["target"] } }
      expect(winds).to eq(winds.uniq)
    end
  end

  it "only uses up items by using them, one at a time, never below zero" do
    each_step do |_, before, _, after, events|
      before["items"].each do |id, item|
        used = events.count { |e| e["type"] == "item_used" && e["item"] == id }
        expect(after["items"][id]["count"]).to eq(item["count"] - used)
        expect(after["items"][id]["count"]).to be >= 0
      end
    end
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
        when "revive", "second_wind" then down.delete(e["target"])
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

  it "gives each unit at most one turn per round, a hasted one at most one quick go besides, and One More at most one more" do
    each_step do |_, before, _, _, events|
      events.slice_before { |e| e["type"] == "round_start" }.each do |round|
        turns, quick = of_type(round, :turn_start).partition { |e| !e["quick"] }
        turns = turns.map { |e| e["unit"] }
        quickened, quick = quick.partition { |e| e["reason"] == "quick" }.map { |list| list }
        quickened = quickened.map { |e| e["unit"] }
        again, hasty = quick.partition { |e| e["reason"] == "one_more" }.map { |list| list.map { |e| e["unit"] } }
        expect(turns).to eq(turns.uniq)
        expect(hasty).to eq(hasty.uniq)
        expect(again).to eq(again.uniq)
        # A Quick: once a round each, only for whoever a Quick named.
        expect(quickened).to eq(quickened.uniq)
        expect(quickened - of_type(round, :quick).map { |e| e["target"] }).to be_empty
        hasted = before["units"].select { |u| u["statuses"].any? { |s| s["kind"] == "haste" } }.map { |u| u["id"] }
        expect(hasty - hasted).to be_empty
        expect(again - of_type(round, :one_more).map { |e| e["actor"] }).to be_empty
        expect(of_type(round, :one_more)).to all(satisfy { |e| before.dig("rules", "one_more") })
      end
    end
  end

  it "knocks down only on a weakness or a critical hit, once, and never gives One More for someone already down" do
    each_step do |_, _, _, _, events|
      events.each_with_index do |event, i|
        next unless event["type"] == "status_applied" && event["status"] == "down"

        # Any blow on it in the go that knocked it down: a multi-hit move needs only one to find the weakness.
        go = events[0...i].rindex { |e| e["type"] == "turn_start" }
        hits = events[go...i].select { |e| e["type"] == "damage" && e["target"] == event["target"] }
        expect(hits).to include(satisfy { |e| e["crit"] || e["effectiveness"].to_i > 100 })
      end
      of_type(events, :one_more).each { |e| expect(e["downed"]).not_to be_empty }
      # The other go is the same move, whoever's side it's on.
      events.each_with_index do |event, i|
        next unless event["type"] == "one_more"

        # A Mimic's copy is the Mimic's doing: the move is the Mimic.
        moves = ->(list) { list.select { |e| %w[attack cast].include?(e["type"]) && e["actor"] == event["actor"] && !e["mimicked"] } }
        before = moves.(events[0...i]).last
        after = moves.(events[(i + 1)..]).first
        # A desperation move isn't the command: the other go is the command's move.
        desperate = events[0...i].any? { |e| e["type"] == "desperation" && e["actor"] == event["actor"] }
        expect(after["ability"]).to eq(before["ability"]) if before && after && !before["desperation"] && !desperate
      end
    end
  end

  it "goes All-Out only for the party, after a One More, with every enemy it names down, and at most once a round" do
    each_step do |_, before, _, _, events|
      events.slice_before { |e| e["type"] == "round_start" }.each do |round|
        expect(of_type(round, :all_out).size).to be <= 1
      end
      events.each_with_index do |event, i|
        next unless event["type"] == "all_out"

        expect(before.dig("rules", "one_more")).to be_truthy
        expect(before["units"].find { |u| u["id"] == event["actor"] }["side"]).to eq("party")
        expect(events[0...i].map { |e| e["type"] }).to include("one_more")
        downed = events[0...i].select { |e| e["type"] == "status_applied" && e["status"] == "down" }.map { |e| e["target"] }
        expect(event["targets"] - downed).to be_empty
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
      next if of_type(events, :victory).any? # a GM ending the fight still rolls the drops

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
