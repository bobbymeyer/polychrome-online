# frozen_string_literal: true

# Build-order step 1's exit criterion: a full battle replays exactly.
RSpec.describe Battle::Replay do
  # A GM-run boss fight, played as a table would: players choosing
  # commands, one player timing out, the GM auto-piloting an absent player
  # and nudging HP (logged), until the fight ends.
  def play_boss_fight(seed)
    state = build_battle(seed: seed, enemies: BattleFixtures.ogre + BattleFixtures.goblins(2), escapable: false)
    actions = []
    step = lambda do |action|
      state, = Battle::Resolver.apply(state, action)
      actions << Battle::State.normalize(action)
    end

    step.(gm("set_hp", unit: "ogre", value: 300, note: "wounded from the last fight"))
    until state["status"] != "input" || state["round"] > 60
      alive = ->(id) { unit(state, id)&.dig("hp")&.positive? }
      awaiting = lambda do |id|
        u = unit(state, id)
        u && alive.(id) && !state["inputs"].key?(id) && u["statuses"].none? { |s| %w[sleep paralyze].include?(s["kind"]) }
      end
      target = %w[goblin_a goblin_b ogre].find(&alive)

      step.(command("bartz", state["round"] == 1 ? "war_cry" : "double_cut", target)) if awaiting.("bartz")
      if awaiting.("vivi")
        spell = unit(state, "vivi")["mp"] >= 10 && state["round"].odd? ? "firaga_all" : "attack"
        step.(command("vivi", spell))
      end
      if awaiting.("rosa")
        hurt = %w[bartz vivi rosa locke].select(&alive).min_by { |id| unit(state, id)["hp"] }
        fallen = %w[bartz vivi locke].reject(&alive).first
        mp = unit(state, "rosa")["mp"]
        if fallen && mp >= 10 then step.(command("rosa", "raise", fallen))
        elsif mp >= 4 then step.(command("rosa", "cure", hurt))
        else step.(command("rosa"))
        end
      end
      break if state["status"] != "input"

      if awaiting.("locke")
        # Locke's player is away: every third round the GM auto-pilots,
        # otherwise the input timer runs out.
        step.((state["round"] % 3).zero? ? gm("auto", unit: "locke") : { type: "timeout" })
      elsif state["inputs"].any?
        step.({ type: "timeout" })
      end
    end

    [build_battle(seed: seed, enemies: BattleFixtures.ogre + BattleFixtures.goblins(2), escapable: false), actions, state]
  end

  it "plays a boss fight to a conclusion" do
    _, actions, final = play_boss_fight(2026)
    expect(%w[victory defeat]).to include(final["status"])
    expect(actions.size).to be > 10
  end

  it "reproduces the final state and the full event log exactly" do
    initial, actions, final = play_boss_fight(2026)

    live_events = []
    actions.reduce(initial) do |state, action|
      state, events = Battle::Resolver.apply(state, action)
      live_events.concat(events)
      state
    end

    replayed_state, replayed_events = described_class.run(initial, actions)
    expect(replayed_state).to eq(final)
    expect(replayed_events.map { |e| e.except("step") }).to eq(live_events)
  end

  it "survives a round trip of the whole record through JSON" do
    initial, actions, final = play_boss_fight(77)
    stored = JSON.generate("initial" => initial, "actions" => actions)
    loaded = JSON.parse(stored)
    expect(described_class.run(loaded["initial"], loaded["actions"]).first).to eq(final)
  end

  it "tags every event with the action that produced it" do
    initial, actions, = play_boss_fight(5)
    _, events = described_class.run(initial, actions)
    expect(events.map { |e| e["step"] }).to eq(events.map { |e| e["step"] }.sort)
    expect(events.first).to include("type" => "gm_override", "step" => 0, "note" => "wounded from the last fight")
  end

  it "diverges for a different seed" do
    _, actions, = play_boss_fight(1)
    initial_a = build_battle(seed: 1, enemies: BattleFixtures.ogre + BattleFixtures.goblins(2), escapable: false)
    initial_b = initial_a.merge("seed" => 2, "rng" => 2)
    prefix = actions.first(5) # the GM tweak plus the whole first round
    expect(described_class.run(initial_a, prefix).last).not_to eq(described_class.run(initial_b, prefix).last)
  end
end
