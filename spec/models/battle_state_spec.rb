# frozen_string_literal: true

require "rails_helper"

RSpec.describe BattleState do
  let(:state) { build_battle }
  let(:field) { described_class.new(state) }

  it "reads the resolver's units without copying them: the engine's hash is still the truth" do
    bartz = field.unit("bartz")
    expect(bartz).to have_attributes(name: "Bartz", side: "party", party?: true, enemy?: false, guest?: false, gone?: false,
                                     hp: 120, max_hp: 120, standing?: true, ko?: false, hurt?: false, hp_band: "ok")
    expect(bartz.to_h).to equal(unit(state, "bartz"))
    expect(field.on_field("enemy").map(&:id)).to eq(%w[goblin_a goblin_b goblin_c])
    expect(field.unit_name("goblin_b")).to eq("Goblin B")
    expect(field.unit_name("nobody_here")).to eq("Nobody here")
  end

  it "says how a unit is doing from its HP, as every HP bar does" do
    goblin = field.unit("goblin_a")
    goblin.to_h["hp"] = 10
    expect(goblin).to have_attributes(hurt?: true, hp_percent: 22, hp_band: "danger")
    goblin.to_h["hp"] = 0
    expect(goblin).to have_attributes(ko?: true, standing?: false, hp_band: "ko")
    expect(field.targetable.map(&:id)).not_to include("goblin_a")
  end

  it "knows the round's commands, and which are players' ideas waiting on the GM" do
    after, = apply(state, command("bartz", "attack", "goblin_a"))
    after, = apply(after, { type: "command", actor: "vivi", command: { kind: "custom", text: "Kick the brazier" } })
    field = described_class.new(after)
    expect(field.command_for(field.unit("bartz"))).to include("ability" => "attack", "target" => "goblin_a")
    expect(field.chosen?(field.unit("rosa"))).to be(false)
    expect(field.ideas_awaiting_ruling.keys).to eq([ "vivi" ])
    expect(field.awaiting_input).not_to include("bartz", "vivi")
  end

  it "asks the engine's questions of the plain hash" do
    vivi = field.unit("vivi")
    fire = field.ability("fire")
    expect(field.usable?(vivi, fire)).to be(true)
    expect(field.target_options(vivi, fire)).to include("goblin_a")
    vivi.to_h["mp"] = 0
    expect(field.usable?(vivi, fire)).to be(false)
  end
end
