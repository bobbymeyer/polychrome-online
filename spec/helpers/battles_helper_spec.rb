# frozen_string_literal: true

require "rails_helper"

RSpec.describe BattlesHelper, type: :helper do
  # Every event type the resolver emits, from the chaotic seeded battles
  # the engine's property specs use.
  let(:steps) { RandomTable.played(1..60).flat_map(&:steps) }

  it "describes every event without raising, and never describes bookkeeping" do
    silent = %w[command_accepted turn_order turn_start turn_end round_end]
    steps.each do |_, _, after, events|
      events.each do |event|
        line = helper.battle_log_line(event, after)
        if silent.include?(event["type"])
          expect(line).to be_nil
        elsif event["type"] != "status_expired" && event["type"] != "timeout"
          expect(line).to be_a(String).and(be_present), "no line for #{event}"
        end
      end
    end
  end

  it "always writes a line for a GM override (§12)" do
    overrides = steps.flat_map { |_, _, after, events| events.select { |e| e["type"] == "gm_override" }.map { |e| [ e, after ] } }
    expect(overrides).not_to be_empty
    overrides.each { |event, state| expect(helper.battle_log_line(event, state)).to start_with("GM ") }
  end

  it "names units and abilities" do
    state = build_battle
    expect(helper.battle_log_line({ "type" => "cast", "actor" => "vivi", "ability" => "fire" }, state)).to eq("Vivi casts Fire.")
    expect(helper.battle_log_line({ "type" => "cast", "actor" => "bartz", "ability" => "double_cut" }, state)).to eq("Bartz uses Double Cut.")
    expect(helper.battle_log_line({ "type" => "damage", "target" => "goblin_a", "amount" => 9, "weak" => true }, state))
      .to eq("Goblin A takes 9 damage. It's super effective!")
    expect(helper.battle_log_line({ "type" => "victory", "rewards" => { "exp" => 18, "gil" => 36 } }, state)).to eq("Victory! 18 EXP and 36 gil.")
  end
end
