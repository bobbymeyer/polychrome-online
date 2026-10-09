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
    expect(field.command_for(field.unit("bartz"))).to have_attributes(ability?: true, ability: "attack", target: "goblin_a", custom?: false)
    expect(field.command_for("vivi")).to have_attributes(custom?: true, text: "Kick the brazier", ruled?: false, awaiting_ruling?: true)
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

  it "reads what the battle copied in from the books: a unit's abilities in its order, and the party's items" do
    field = described_class.new(build_battle(items: { "potion" => { "id" => "potion", "name" => "Potion", "target" => "single_ally", "count" => 2,
                                                                    "effects" => [ { "primitive" => "heal", "power" => 30 } ] } }))
    vivi = field.unit("vivi")
    expect(field.abilities_of(vivi).map(&:id)).to eq(vivi.abilities)
    expect(field.ability("fire")).to have_attributes(name: "Fire", ability?: true, item?: false, magic?: true, target: "single_enemy")
    expect(field.item("potion")).to have_attributes(name: "Potion", item?: true, count: 2, target: "single_ally")
    expect(field.target_options(vivi, field.item("potion"))).to include("bartz", "vivi")
    expect(field.item_name("elixir")).to eq("Elixir")
  end

  it "reads a unit's last command, its default when the clock runs out" do
    expect(field.unit("bartz").last_command).to be_nil
    finished, = apply(state, { type: "timeout" })
    expect(described_class.new(finished).unit("bartz").last_command).to have_attributes(ability?: true, ability: "attack")
  end
end
