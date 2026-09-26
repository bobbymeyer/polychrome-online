# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/base_world")

RSpec.describe "Battle screen", type: :request do
  let(:battle) { start_battle }

  def sit(seat)
    post battle_seat_path(battle), params: { seat: seat }
  end

  def command!(params)
    post battle_actions_path(battle), params: { command: params }
  end

  def gm!(params)
    post battle_actions_path(battle), params: { gm: params }
  end

  describe "setting up" do
    let!(:world) { Seeds::BaseWorld.run }

    it "starts a battle from the books and seats the creator as GM" do
      get new_world_battle_path(world)
      expect(response).to have_http_status(:ok)

      post world_battles_path(world), params: { battle: {
        name: "Ambush", seed: "42", escapable: "1", input_seconds: "60",
        party: { "0" => { name: "Bartz", job: "knight" }, "1" => { name: "", job: "white_mage" }, "2" => { name: "", job: "" } },
        encounter: { "0" => { monster: "goblin", count: "3" }, "1" => { monster: "", count: "1" } }
      } }
      battle = BattleRecord.last
      expect(response).to redirect_to(battle_path(battle))
      expect(battle).to have_attributes(name: "Ambush", seed: 42, input_seconds: 60)
      expect(battle.units.map { |u| u["name"] }).to eq([ "Bartz", "White Mage", "Goblin A", "Goblin B", "Goblin C" ])

      get battle_panel_path(battle)
      expect(response.body).to include("Game Master · Round 1")
    end

    it "needs a party and an encounter" do
      post world_battles_path(world), params: { battle: {
        name: "Empty", party: { "0" => { name: "", job: "" } }, encounter: { "0" => { monster: "goblin", count: "1" } }
      } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("at least one party member")
    end

    it "lists a world's battles" do
      start_battle(world: world)
      get world_battles_path(world)
      expect(response.body).to include("Test battle")
    end
  end

  describe "the page" do
    it "renders the board from the current state, with a lazily loaded command panel" do
      get battle_path(battle)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-controller="battle-player"', "turbo-cable-stream-source",
                                        'data-unit="goblin_a"', 'data-roster="bartz_1"', 'id="command_panel"')
    end

    it "shows the log so far to a late joiner, without replaying anything" do
      battle.apply!({ "type" => "gm_override", "op" => "set_hp", "unit" => "goblin_a", "value" => 5, "note" => "wounded" }, actor: "gm")
      get battle_path(battle)
      expect(response.body).to include("GM sets Goblin A&#39;s HP to 5. &quot;wounded&quot;")
    end

    it "never shows enemy HP on the shared board" do
      get battle_path(battle)
      board = response.body[/<div class="board">.*?<ol class="roster/m]
      expect(board).not_to include("data-hp")
    end
  end

  describe "seats" do
    it "offers seats until one is taken" do
      get battle_panel_path(battle)
      expect(response.body).to include("Take a seat", "Game Master", "Bartz", "Faris")

      sit("bartz_1")
      get battle_panel_path(battle)
      expect(response.body).to include("Seated as <strong>Bartz</strong>", "Attack", "Cure", "Defend")
    end

    it "ignores seats that aren't party members" do
      sit("goblin_a")
      get battle_panel_path(battle)
      expect(response.body).to include("Take a seat")
    end

    it "can be left" do
      sit("gm")
      delete battle_seat_path(battle)
      follow_redirect!
      expect(response.body).to include("Take a seat")
    end
  end

  describe "players" do
    before { sit("bartz_1") }

    it "pick a target, then submit, and get a placeholder that holds no battle state" do
      get battle_panel_path(battle, ability: "attack")
      expect(response.body).to include("data-choosing", "Goblin A", "Goblin B")

      command!(kind: "ability", ability: "attack", target: "goblin_b")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-resolving")
      expect(response.body).not_to include("Goblin", "Round", "HP")
      expect(battle.reload.state["inputs"]["bartz_1"]).to include("target" => "goblin_b")
    end

    it "always act as their own seat, whatever the params say" do
      post battle_actions_path(battle), params: { command: { kind: "defend" }, actor: "faris_2" }
      expect(battle.reload.state["inputs"].keys).to eq([ "bartz_1" ])
      expect(battle.battle_actions.last.actor).to eq("bartz_1")
    end

    it "see the waiting state after submitting, and can change their command" do
      command!(kind: "defend")
      get battle_panel_path(battle)
      expect(response.body).to include("Ready: <strong>Defend</strong>", "Waiting for Faris", "Change command")
      get battle_panel_path(battle, change: 1)
      expect(response.body).to include("Attack")
    end

    it "get the resolver's reason when an action is illegal" do
      command!(kind: "ability", ability: "attack", target: "faris_2")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("faris_2 is not an enemy")
    end

    it "cannot send GM overrides" do
      gm!(op: "set_hp", unit: "goblin_a", value: 0)
      expect(response).to have_http_status(:forbidden)
      expect(battle.reload.battle_actions).to be_empty
    end

    it "cannot change the playback speed" do
      patch battle_playback_path(battle), params: { speed: 4 }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "the GM" do
    before { sit("gm") }

    it "sees every unit's HP and who the round is waiting on" do
      get battle_panel_path(battle)
      expect(response.body).to include("Auto Bartz", "Auto Faris", "Run the round now", "Goblin A", "50/50")
    end

    it "auto-pilots an absent player and runs the round, all logged" do
      gm!(op: "auto", unit: "bartz_1")
      gm!(op: "execute_round")
      battle.reload
      expect(battle.round).to eq(2)
      expect(battle.battle_actions.map(&:actor)).to eq(%w[gm gm])
      expect(battle.battle_events.where(kind: "gm_override").count).to eq(2)
    end

    it "applies overrides with a note" do
      gm!(op: "set_hp", unit: "goblin_a", value: "7", note: "an old wound", status: "", turns: "")
      override = battle.reload.battle_events.find_by(kind: "gm_override").payload
      expect(override).to include("op" => "set_hp", "unit" => "goblin_a", "hp" => 7, "note" => "an old wound")
      expect(battle.unit("goblin_a")["hp"]).to eq(7)

      gm!(op: "add_status", unit: "goblin_b", status: "poison", turns: "2")
      expect(battle.reload.unit("goblin_b")["statuses"]).to eq([ { "kind" => "poison", "turns" => 2 } ])
    end

    it "ends the battle" do
      gm!(op: "end_battle", result: "fled")
      get battle_panel_path(battle)
      expect(response.body).to include("The party got away.", "replays exactly from seed 7")
    end

    it "sets the playback speed for everyone" do
      patch battle_playback_path(battle), params: { speed: 2 }
      expect(battle.reload.playback_speed).to eq(2)
    end

    it "cannot command a party member's unit" do
      command!(kind: "defend")
      expect(response).to have_http_status(:forbidden)
    end
  end
end
