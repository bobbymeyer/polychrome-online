# frozen_string_literal: true

require "rails_helper"

RSpec.describe BattleRecord do
  include SignIn
  include ActiveJob::TestHelper

  let(:battle) { start_battle }
  let(:bartz) { battle.party.first.id }
  let(:faris) { battle.party.second.id }

  def command(actor, kind: "ability", ability: "attack", target: nil)
    { "type" => "command", "actor" => actor, "command" => { "kind" => kind, "ability" => ability, "target" => target }.compact }
  end

  def run_round(battle)
    battle.awaiting_input.each { |id| battle.apply!(command(id), actor: id) }
  end

  it "starts from the books with the initial state stored alongside" do
    expect(battle).to be_persisted
    expect(battle.model_name.param_key).to eq("battle")
    expect(battle.initial_state).to eq(battle.state)
    expect(battle.units.map(&:id)).to eq([ bartz, faris, "goblin_a", "goblin_b" ])
    bartz_character = battle.campaign.characters.find_by!(name: "Bartz")
    expect(bartz).to eq("character_#{bartz_character.id}")
    expect(battle.party.first.to_h).to include("name" => "Bartz", "abilities" => [ "attack", "cure" ],
                                          "image" => { "book" => "jobs", "slug" => "knight" },
                                          "stats" => bartz_character.stats)
    expect(battle.unit("goblin_a").image).to eq("book" => "monsters", "slug" => "goblin")
  end

  describe "#gm_override" do
    it "turns a ruling's quick choices into engine effects" do
      action = battle.gm_override("op" => "rule", "unit" => bartz, "effect" => "damage", "strength" => "heavy", "type" => "fire", "value" => "3")
      expect(action).to include("type" => "gm_override", "actor" => "gm", "op" => "rule", "value" => 3,
                                "effects" => [ { "primitive" => "elemental", "type" => "fire", "power" => 40 } ])
      expect(action).not_to include("strength", "type" => "fire")
      expect(battle.gm_override("op" => "rule", "unit" => bartz, "effect" => "status")["effects"]).to eq([])
    end

    it "refuses a skill or a monster the world hasn't got" do
      expect { battle.gm_override("op" => "rule", "unit" => bartz, "stat" => "skill:juggling") }.to raise_error(Battle::InvalidAction, /juggling|skill/)
      expect { battle.gm_override("op" => "add_unit", "side" => "enemy", "monster" => "nobody") }.to raise_error(Battle::InvalidAction)
    end

    it "brings a guest from the Bestiary under the GM's name for them, earning and dropping nothing" do
      action = battle.gm_override("op" => "add_unit", "side" => "party", "monster" => "goblin", "name" => "Cid")
      expect(action["unit"]).to include("name" => "Cid", "id" => "cid", "rewards" => {}, "drops" => [])
      expect(action).not_to have_key("monster")
    end
  end

  describe "#apply!" do
    it "persists the action and its events in order and advances the state" do
      before, events = battle.apply!(command(bartz), actor: bartz)
      expect(before["inputs"]).to eq({})
      expect(events.map { |e| e["type"] }).to eq([ "command_accepted" ])
      expect(battle.reload.state["inputs"]).to have_key(bartz)

      battle.apply!(command(faris), actor: faris)
      battle.reload
      expect(battle.round).to eq(2)
      expect(battle.battle_actions.map { |a| [ a.position, a.actor ] }).to eq([ [ 0, bartz ], [ 1, faris ] ])
      expect(battle.battle_events.map(&:position)).to eq((0...battle.battle_events.size).to_a)
      expect(battle.battle_events.map(&:kind)).to include("round_start", "turn_start", "round_end")
    end

    it "replays exactly from initial state and the action log (§4)" do
      4.times { run_round(battle) unless battle.reload.over? }
      battle.reload
      state, events = battle.replay
      expect(state).to eq(battle.state)
      expect(events.map { |e| e.except("step") }).to eq(battle.battle_events.map(&:payload))
    end

    it "saves nothing when the resolver rejects the action" do
      expect { battle.apply!(command("goblin_a"), actor: "goblin_a") }.to raise_error(Battle::InvalidAction)
      expect(battle.reload.battle_actions).to be_empty
      expect(battle.state).to eq(battle.initial_state)
    end

    it "broadcasts one beat per action" do
      expect { battle.apply!(command(bartz), actor: bartz) }
        .to have_broadcasted_to(turbo_stream_for(battle)).with(a_string_including("battle-beat", "battle_beats"))
    end

    it "records the battle's end" do
      battle.apply!({ "type" => "gm_override", "op" => "end_battle", "result" => "victory" }, actor: "gm")
      expect(battle.reload).to be_over
      expect(battle.status).to eq("victory")
    end
  end

  it "gives the first of a kind a name of its own: who the place's past says waits there" do
    named = start_battle(names: { "goblin" => "Sten Pike" })
    expect(named.enemies.map(&:name)).to eq([ "Sten Pike", "Goblin B" ])
  end

  describe "input timer" do
    let(:battle) { start_battle(input_seconds: 30) }

    it "arms a timeout job for each round" do
      expect(battle.deadline_at).to be_within(2.seconds).of(30.seconds.from_now)
      expect(BattleTimeoutJob).to have_been_enqueued.with(battle, 1)

      run_round(battle)
      expect(battle.reload.round).to eq(2)
      expect(battle.deadline_at).to be_within(2.seconds).of(30.seconds.from_now + BattleRecord::ANIMATION_GRACE)
      expect(BattleTimeoutJob).to have_been_enqueued.with(battle, 2)
    end

    it "runs the round with defaults when the deadline passes" do
      battle.apply!(command(bartz), actor: bartz)
      battle.watch! # someone has it open
      travel_to(battle.deadline_at + 1.second) do
        BattleTimeoutJob.perform_now(battle.reload, 1)
      end
      battle.reload
      expect(battle.round).to eq(2)
      expect(battle.battle_actions.last).to have_attributes(actor: "system", payload: { "type" => "timeout" })
      expect(battle.battle_events.find_by(kind: "timeout").payload["defaulted"]).to eq([ faris ])
    end

    it "holds the round when nobody has the battle open, and starts the clock again when someone does" do
      battle.watch!
      travel_to(battle.deadline_at + BattleRecord::WATCHERS_GONE) do
        expect { BattleTimeoutJob.perform_now(battle.reload, 1) }.not_to change(BattleAction, :count)
        expect(battle.reload).to have_attributes(round: 1, deadline_at: nil)
        expect(battle).to be_held

        expect { battle.watch! }.to have_broadcasted_to(turbo_stream_for(battle)).with(a_string_including("battle_countdown"))
        expect(battle.reload.deadline_at).to be_within(2.seconds).of(30.seconds.from_now)
        expect(battle).not_to be_held
      end
    end

    it "ignores a timer for a round that already ran" do
      run_round(battle)
      travel_to(1.hour.from_now) do
        expect { BattleTimeoutJob.perform_now(battle.reload, 1) }.not_to change(BattleAction, :count)
      end
    end

    it "ignores a timer that fires early" do
      expect { BattleTimeoutJob.perform_now(battle, 1) }.not_to change(BattleAction, :count)
    end

    describe "never running out on someone who isn't there" do
      let(:campaign) { create_campaign }
      let(:battle) do
        create_character(campaign, name: "Bartz", user: make_user("Kim"))
        create_character(campaign, name: "Faris", user: make_user("Sam"))
        start_battle(campaign: campaign, input_seconds: 30)
      end

      it "starts the first round's clock once every player is ready" do
        expect(battle.deadline_at).to be_nil
        expect(battle.still_coming).to eq([ bartz, faris ])

        expect { battle.arrive!(bartz) }.to have_broadcasted_to(turbo_stream_for(battle)).with(a_string_including("when Faris is ready"))
        expect(battle.deadline_at).to be_nil
        expect { battle.arrive!(faris) }.to have_broadcasted_to(turbo_stream_for(battle)).with(a_string_including("battle_countdown"))
        expect(battle.deadline_at).to be_within(2.seconds).of(30.seconds.from_now)
        expect(BattleTimeoutJob).to have_been_enqueued.with(battle, 1)
      end

      it "doesn't wait for someone the GM has put on auto" do
        battle.arrive!(bartz)
        battle.set_auto!(faris, true)
        expect(battle.deadline_at).to be_within(2.seconds).of(30.seconds.from_now)
      end

      it "stops the clock while the GM rules on an idea, and gives time to choose after" do
        [ bartz, faris ].each { |id| battle.arrive!(id) }
        battle.apply!({ "type" => "command", "actor" => bartz, "command" => { "kind" => "custom", "text" => "Kick the brazier", "target" => "goblin_a" } }, actor: bartz)
        expect(battle.reload).to be_ruling_pending

        travel_to(battle.deadline_at + 1.second) do
          expect { BattleTimeoutJob.perform_now(battle.reload, 1) }.not_to change(BattleAction, :count)
          battle.apply!({ "type" => "gm_override", "op" => "rule", "unit" => bartz, "stat" => "str", "difficulty" => "normal",
                          "success" => "It topples.", "failure" => "It won't budge." }, actor: "gm")
          expect(battle.reload.deadline_at).to be_within(2.seconds).of(BattleRecord::AFTER_RULING.from_now)
          expect(battle.round).to eq(1)
        end
      end
    end
  end

  it "runs a round nobody can choose in at once, until someone can" do
    battle = start_battle(goblins: 1, input_seconds: 30)
    bartz, faris = battle.party.map(&:id)
    [ bartz, faris ].each do |id|
      battle.apply!({ "type" => "gm_override", "op" => "set_hp", "unit" => id, "value" => 999 }, actor: "gm")
      battle.apply!({ "type" => "gm_override", "op" => "add_status", "unit" => id, "status" => "stop", "turns" => 3 }, actor: "gm")
    end
    battle.apply!({ "type" => "gm_override", "op" => "execute_round" }, actor: "gm")
    expect(battle.reload.round).to be > 2 # the stopped rounds ran by themselves
    expect(battle.over? || battle.awaiting_input.any?).to be(true)
  end

  it "stops running rounds by itself after QUIET_ROUNDS, one beat broadcast for each, when nobody can ever choose" do
    battle = start_battle(goblins: 1, input_seconds: 30)
    battle.party.each do |unit|
      battle.apply!({ "type" => "gm_override", "op" => "set_hp", "unit" => unit.id, "value" => 9999 }, actor: "gm")
      battle.apply!({ "type" => "gm_override", "op" => "add_status", "unit" => unit.id, "status" => "stop", "turns" => 99 }, actor: "gm")
    end
    goblin = battle.enemies.sole.id
    battle.apply!({ "type" => "gm_override", "op" => "set_hp", "unit" => goblin, "value" => 9999 }, actor: "gm")
    battle.apply!({ "type" => "gm_override", "op" => "add_status", "unit" => goblin, "status" => "stop", "turns" => 99 }, actor: "gm")
    round = battle.round
    actions = battle.battle_actions.count

    expect { battle.apply!({ "type" => "gm_override", "op" => "execute_round" }, actor: "gm") }
      .to have_broadcasted_to(turbo_stream_for(battle)).with(a_string_including("battle_beats")).exactly(BattleRecord::QUIET_ROUNDS + 1).times
    expect(battle.reload.round).to eq(round + 1 + BattleRecord::QUIET_ROUNDS)
    expect(battle.battle_actions.count - actions).to eq(1 + BattleRecord::QUIET_ROUNDS)
    expect(battle.battle_actions.last.payload).to include("type" => "timeout")
    expect(battle).not_to be_over
    expect(battle.awaiting_input).to be_empty # the round waits for the timer, or the GM
  end

  describe "bosses" do
    it "calls everyone at the table into the battle when it starts" do
      campaign = create_campaign
      expect { start_battle(campaign: campaign) }
        .to have_broadcasted_to(stream(campaign, :stage)).with(a_string_including("battle_start", "/battles/", 'boss="false"'))
    end

    it "is a boss fight when a marked boss is in it, and names it on victory" do
      campaign = create_campaign
      campaign.world.monsters.find_by!(slug: "goblin").update!(boss: true, boss_line: "Mine!")
      boss_battle = nil
      expect { boss_battle = start_battle(campaign: campaign) }
        .to have_broadcasted_to(stream(campaign, :stage)).with(a_string_including('boss="true"'))
      expect(boss_battle).to be_boss
      expect(boss_battle.boss_monsters.map(&:slug)).to eq([ "goblin" ])

      boss_battle.apply!({ "type" => "gm_override", "op" => "end_battle", "result" => "victory" }, actor: "gm")
      expect(boss_battle.campaign.messages.last.body).to include("Victory!", "Goblin has fallen!")
    end

    it "names a boss who has a name of their own when they fall" do
      campaign = create_campaign
      campaign.world.monsters.find_by!(slug: "goblin").update!(boss: true)
      boss_battle = start_battle(campaign: campaign, names: { "goblin" => "Roz Tennant" })
      expect(boss_battle.boss_names).to eq([ "Roz Tennant" ])
      boss_battle.apply!({ "type" => "gm_override", "op" => "end_battle", "result" => "victory" }, actor: "gm")
      expect(boss_battle.campaign.messages.last.body).to include("Roz Tennant has fallen!")
    end

    it "holds the first clock for the boss's entrance" do
      campaign = create_campaign
      boss_battle = start_battle(campaign: campaign, boss: true, input_seconds: 30)
      boss_battle.open_round!
      expect(boss_battle.deadline_at).to be_within(2.seconds).of((30.seconds + BattleRecord::BOSS_ENTRANCE).from_now)
    end

    it "is a boss fight when started from a boss room, with its strongest monster as the boss" do
      campaign = create_campaign
      boss_battle = start_battle(campaign: campaign, boss: true)
      expect(boss_battle).to be_boss
      expect(boss_battle.boss_monsters.map(&:slug)).to eq([ "goblin" ])
      plain = start_battle(campaign: campaign)
      expect(plain).not_to be_boss
      expect(plain.boss_monsters).to be_empty
    end
  end

  describe "settlement" do
    let(:campaign) { battle.campaign }
    let(:characters) { battle.characters_by_unit }

    def win!(battle)
      battle.apply!({ "type" => "gm_override", "op" => "end_battle", "result" => "victory" }, actor: "gm")
    end

    it "splits EXP among the standing, gives each their job ABP, and pays the party" do
      battle.apply!({ "type" => "gm_override", "op" => "set_hp", "unit" => faris, "value" => 0 }, actor: "gm")
      bartz_character = characters[bartz]
      exp_before = bartz_character.exp
      win!(battle)

      bartz_character.reload
      expect(bartz_character.exp).to eq(exp_before + 20) # 2 goblins x 10 EXP, one standing
      expect(bartz_character.character_job.abp).to eq(1 + 4) # started at job level 1, +2 ABP per goblin
      expect(characters[faris].reload.exp).to eq(Stats::Growth.exp_for_level(5))
      expect(campaign.reload.gil).to eq(10)
      expect(battle.reload.settlement).to include("result" => "victory", "gil" => 10,
                                                  "members" => [ { "name" => "Bartz", "exp" => 20, "abp" => 4, "job_level" => [ 1, 4 ], "learned" => [], "to_next" => 80 } ])
    end

    it "writes HP and MP back to the characters" do
      battle.apply!({ "type" => "gm_override", "op" => "set_hp", "unit" => bartz, "value" => 3 }, actor: "gm")
      battle.apply!({ "type" => "gm_override", "op" => "end_battle", "result" => "fled" }, actor: "gm")
      expect(characters[bartz].reload.current_hp).to eq(3)
      expect(battle.reload.settlement).to include("result" => "fled", "members" => [])
      expect(campaign.reload.gil).to eq(0)
    end

    it "puts drops in the party bag" do
      potion = create_item(campaign.world, slug: "potion", category: "consumable", stats: {}, target: "single_ally",
                                           effects: [ { primitive: "heal", power: 30 } ])
      campaign.world.monsters.find_by!(slug: "goblin").update!(drops: [ { item: "potion", chance: 100 } ])
      battle = start_battle(campaign: campaign)
      win!(battle)
      expect(campaign.quantity_of(potion)).to eq(2)
      expect(battle.reload.settlement["drops"]).to eq(%w[Potion Potion])
    end

    it "reports level-ups and newly learned abilities" do
      wyrm_world = campaign.world
      wyrm_world.monsters.find_by!(slug: "goblin").update!(exp: 500, abp: 30)
      heal = create_ability(wyrm_world, slug: "shield_bash", kind: "skill", effects: [ { primitive: "physical", power: 90 } ])
      wyrm_world.jobs.find_by!(slug: "knight").job_levels.create!(level: 2, ability: heal)
      battle = start_battle(campaign: campaign)
      win!(battle)
      member = battle.reload.settlement["members"].find { |m| m["name"] == "Bartz" }
      expect(member["level"]).to eq([ 5, 8 ]) # 200 + 1000 / 2 = 700 EXP
      expect(member["learned"]).to eq([ "Shield bash" ])
    end

    it "knocks out whoever is still standing when the GM calls a defeat" do
      battle.apply!({ "type" => "gm_override", "op" => "end_battle", "result" => "defeat" }, actor: "gm")
      expect(characters.values.map { |c| c.reload.current_hp }).to eq([ 0, 0 ])
      expect(battle.reload.settlement).to include("result" => "defeat")
    end

    it "happens once" do
      win!(battle)
      expect { battle.send(:settle!, []) }.not_to(change { campaign.reload.gil })
    end
  end

  describe "auto" do
    let(:campaign) { create_campaign }
    let(:battle) do
      create_character(campaign, name: "Bartz").update!(user: User.create!(name: "Jo", email_address: "jo@example.com", password: "a long password"))
      create_character(campaign, name: "Faris")
      start_battle(campaign: campaign)
    end

    it "plays unclaimed characters on auto as each round opens, logged as the GM's call" do
      expect(battle.auto_units).to eq([ faris ])
      expect(battle.awaiting_input).to eq([ bartz ])
      expect(battle.battle_actions.last).to have_attributes(actor: "gm", payload: include("op" => "auto", "units" => [ faris ]))

      battle.apply!(command(bartz), actor: bartz)
      expect(battle.round).to eq(2)
      expect(battle.awaiting_input).to eq([ bartz ])
    end

    it "waits for the GM or the timer when everyone standing is on auto" do
      battle.set_auto!(bartz, true)
      expect(battle.round).to eq(1) # nobody was left to play, so nothing was filled
      battle.apply!({ "type" => "gm_override", "op" => "execute_round" }, actor: "gm")
      expect(battle.round).to eq(2)
      expect(battle.awaiting_input).to contain_exactly(bartz, faris)
    end

    it "fills in at once when the GM switches it on mid-round, and stops when switched off" do
      battle.set_auto!(faris, false)
      battle.apply!(command(bartz), actor: bartz)
      expect(battle.round).to eq(2)
      expect(battle.awaiting_input).to contain_exactly(bartz, faris)

      battle.set_auto!(faris, true)
      expect(battle.awaiting_input).to eq([ bartz ])
    end
  end

  it "sets playback speed for everyone" do
    expect { battle.set_speed!(4) }.to have_broadcasted_to(turbo_stream_for(battle)).with(a_string_including("battle_playback"))
    expect(battle.reload.playback_speed).to eq(4)
    expect { battle.set_speed!(3) }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
