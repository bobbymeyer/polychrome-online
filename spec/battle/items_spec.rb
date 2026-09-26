# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Items and curing in battle" do
  let(:state) { build_battle(seed: 5, items: BattleFixtures.items) }

  def use(actor, item, target = nil) = { type: "command", actor: actor, command: { kind: "item", item: item, target: target } }

  # Everyone else defends, so the round runs and only the item matters.
  def round(state, *item_commands)
    busy = item_commands.map { |c| c[:actor] }
    others = Battle::State.able_to_act(state) - busy
    [ *item_commands, *others.map { |id| command(id, kind: "defend") } ].reduce([ state, [] ]) do |(s, all), action|
      after, events = apply(s, action)
      [ after, all + events ]
    end
  end

  it "builds the party's items into the state, validated like abilities" do
    expect(state["items"]["potion"]).to eq("id" => "potion", "name" => "Potion", "target" => "single_ally",
                                           "effects" => [ { "primitive" => "heal", "power" => 30 } ], "count" => 2)
    expect { build_battle(items: { bad: { name: "Bad", target: "single_ally", effects: [ { primitive: "nope" } ], count: 1 } }) }
      .to raise_error(ArgumentError, /unknown primitive/)
    expect { build_battle(items: { bad: { name: "Bad", target: "single_ally", effects: [ { primitive: "heal", power: 1 } ], count: -1 } }) }
      .to raise_error(ArgumentError, /count/)
  end

  it "uses an item: its effects land, and one is used up" do
    hurt = with_unit(state, "vivi", hp: 20)
    after, events = round(hurt, use("rosa", "potion", "vivi"))
    used = of_type(events, :item_used).sole
    expect(used).to include("actor" => "rosa", "item" => "potion", "name" => "Potion", "targets" => [ "vivi" ], "left" => 1)
    expect(unit(after, "vivi")["hp"]).to be > 20
    expect(after["items"]["potion"]["count"]).to eq(1)
    expect(unit(after, "rosa")["mp"]).to eq(unit(hurt, "rosa")["mp"]) # items cost nothing
  end

  it "works while silenced" do
    silenced = with_unit(with_unit(state, "vivi", hp: 20), "rosa", statuses: [ { "kind" => "silence", "turns" => 3 } ])
    after, = round(silenced, use("rosa", "potion", "vivi"))
    expect(unit(after, "vivi")["hp"]).to be > 20
  end

  it "won't let two players queue the last one" do
    one = state.merge("items" => state["items"].merge("remedy" => state["items"]["remedy"]))
    after, = apply(one, use("rosa", "remedy", "vivi"))
    expect { apply(after, use("bartz", "remedy", "vivi")) }.to raise_error(Battle::InvalidAction, /no Remedy left/)
    # ... but the one who queued it can change their mind
    expect { apply(after, use("rosa", "remedy", "bartz")) }.not_to raise_error
  end

  it "rejects items the party doesn't have, and bad targets" do
    expect { apply(state, use("rosa", "elixir", "vivi")) }.to raise_error(Battle::InvalidAction, /no "elixir"/)
    expect { apply(state, use("rosa", "potion", "goblin_a")) }.to raise_error(Battle::InvalidAction, /not an ally/)
  end

  it "revives with a Phoenix Down, retargeting to a fallen ally" do
    down = with_unit(state, "bartz", hp: 0)
    after, = round(down, use("rosa", "phoenix_down"))
    expect(unit(after, "bartz")["hp"]).to be_positive
  end

  it "never defaults to an item for an absent player" do
    first, = round(state, use("rosa", "potion", "vivi"))
    expect(unit(first, "rosa")["last_command"]).to include("kind" => "item")

    second, events = apply(first, { type: "gm_override", op: "execute_round" }) # everyone defaults
    expect(of_type(events, :item_used)).to be_empty
    expect(second["items"]["potion"]["count"]).to eq(first["items"]["potion"]["count"])
  end

  it "has no items when the party brought none" do
    bare = build_battle(seed: 5)
    expect(bare["items"]).to eq({})
    expect { apply(bare, use("rosa", "potion", "vivi")) }.to raise_error(Battle::InvalidAction)
  end

  describe "cleanse" do
    let(:poisoned) do
      with_unit(state, "vivi", statuses: [ { "kind" => "poison", "turns" => 3 }, { "kind" => "blind", "turns" => 3 },
                                           { "kind" => "haste", "turns" => 3 } ])
    end

    it "cures the one status an Antidote names" do
      after, events = round(poisoned, use("rosa", "antidote", "vivi"))
      expect(unit(after, "vivi")["statuses"].map { |s| s["kind"] }).to contain_exactly("blind", "haste")
      expect(of_type(events, :status_expired).map { |e| [ e["status"], e["reason"] ] }).to include([ "poison", "cured" ])
    end

    it "cures every harmful status, and leaves Haste, with no kind named" do
      after, = round(poisoned, use("rosa", "remedy", "vivi"))
      expect(unit(after, "vivi")["statuses"].map { |s| s["kind"] }).to eq([ "haste" ])
    end

    it "is a miss when there's nothing to cure" do
      _, events = round(state, use("rosa", "remedy", "vivi"))
      expect(of_type(events, :miss).map { |e| e["reason"] }).to include("nothing_to_cure")
    end

    it "is an ability primitive too (Esuna)" do
      healer = build_battle(seed: 5, party: [ BattleFixtures.party.first.merge(abilities: %w[esuna]) ])
      sick = with_unit(healer, "bartz", statuses: [ { "kind" => "blind", "turns" => 3 } ])
      after, = apply(sick, command("bartz", "esuna", "bartz"))
      expect(unit(after, "bartz")["statuses"]).to be_empty
    end

    it "validates the status it names" do
      expect { build_battle(abilities: BattleFixtures.abilities.merge(bad: { name: "Bad", kind: "magic", target: "self", cost: { mp: 0 },
                                                                             effects: [ { primitive: "cleanse", kind: "doom" } ] })) }
        .to raise_error(ArgumentError, /unknown status doom/)
    end
  end
end
