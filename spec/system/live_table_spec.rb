# frozen_string_literal: true

require "rails_helper"

# The table as several people see it at once, each in their own browser:
# what reaches whom, live, without a reload.
RSpec.describe "The live table", type: :system do
  let(:gm) { make_user("Gamemaster") }
  let(:player) { make_user("Player") }
  let(:campaign) { create_campaign.tap { |c| c.update!(gm_id: gm.id) } }
  let!(:rook) { create_character(campaign, name: "Rook", user: player) }

  it "tells the players what the party knows when the GM makes a flag public" do
    seat(player, rook)
    as(player) { expect(page).to have_no_css("#party_knows", text: "Met the king", visible: :all) }

    campaign.flags.create!(key: "met_the_king", value: "yes", public: true)

    as(player) { expect(page).to have_css("#party_knows", text: "Met the king") }
  end

  it "whispers only to the GM and the character involved" do
    watcher = make_user("Watcher", admin: true)
    seat(gm, "gm")
    seat(player, rook)
    seat(watcher, nil)

    campaign.messages.create!(body: "The key is under the mat.", scope: "whisper", recipient: rook)
    campaign.narrate("Night falls.")

    as(gm) { expect(page).to logged?("under the mat").and logged?("Night falls") }
    as(player) do
      expect(page).to logged?("under the mat").and logged?("Night falls")
      # Out of the drawer: on screen under the dialogue box, and the whisper pops up.
      expect(page).to have_css(".recent-lines", text: /under the mat.*Night falls/m)
      expect(page).to have_css(".toast", text: "under the mat")
    end
    as(watcher) do
      expect(page).to logged?("Night falls")
      expect(page).not_to logged?("under the mat")
    end
  end

  it "refreshes the GM's prep when a clock is started elsewhere, keeping a half-written one" do
    seat(gm, "gm")
    as(gm) do
      visit campaign_prep_path(campaign)
      find("#new_clock summary").click
      fill_in "clock_name_#{campaign.id}", with: "Half-typed"
      wait_for_streams
    end

    campaign.clocks.create!(name: "The docks fall", segments: 4)

    as(gm) do
      expect(page).to have_css("#gm_clocks", text: "The docks fall")
      expect(find("#new_clock")[:open]).to be_truthy
      expect(page).to have_field("clock_name_#{campaign.id}", with: "Half-typed")
    end
  end

  # Beats play one after another, animated, so a later line waits on the
  # ones before it.
  it "plays a battle's beats as they happen" do
    battle = start_battle(campaign: campaign, goblins: 1)
    seat(gm, "gm")
    as(gm) do
      visit battle_path(battle)
      wait_for_streams
    end

    goblin = battle.units.find { |u| u["side"] == "enemy" }["id"]
    battle.apply!({ "type" => "command", "actor" => rook.battle_unit_id, "command" => { "kind" => "ability", "ability" => "attack", "target" => goblin } },
                  actor: rook.battle_unit_id)
    as(gm) { expect(page).to have_css("[data-battle-player-target=log]", text: /Rook attacks/, visible: :all, wait: 15) }

    battle.apply!({ "type" => "gm_override", "op" => "end_battle", "result" => "victory" }, actor: "gm")
    as(gm) { expect(page).to have_css("[data-battle-player-target=log]", text: "Victory!", visible: :all, wait: 15) }
  end

  it "takes a player from one battle's results into the next, and starts the clock once they're there" do
    first = start_battle(campaign: campaign, goblins: 1)
    seat(player, rook)
    as(player) do
      visit battle_path(first)
      wait_for_streams
    end
    first.apply!({ "type" => "gm_override", "op" => "end_battle", "result" => "victory" }, actor: "gm")
    as(player) { expect(page).to have_css(".board[data-status=victory]", wait: 15) }

    allow(BattleTimeoutJob).to receive(:set).and_return(instance_double(ActiveJob::ConfiguredJob, perform_later: nil)) # jobs run inline here
    second = start_battle(campaign: campaign, goblins: 1, input_seconds: 60)
    expect(second.deadline_at).to be_nil # Rook hasn't seen it yet
    as(player) do
      expect(page).to have_current_path(battle_path(second), wait: 15)
      expect(page).to have_css(".countdown[data-controller=countdown]", wait: 10)
    end
    expect(second.reload.deadline_at).to be_present
  end
end
