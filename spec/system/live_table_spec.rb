# frozen_string_literal: true

require "rails_helper"

# The table as several people see it at once, each in their own browser:
# what reaches whom, live, without a reload.
RSpec.describe "The live table", type: :system do
  let(:gm) { make_user("Gamemaster") }
  let(:player) { make_user("Player") }
  let(:campaign) { create_campaign.tap { |c| c.update!(gm_id: gm.id) } }
  let!(:rook) { create_character(campaign, name: "Rook", user: player) }

  it "tells the players what the party knows when a secret comes out" do
    seat(player, rook)
    as(player) { expect(page).to have_no_css("#party_knows", text: "Met the king", visible: :all) }

    campaign.secrets.create!(body: "Met the king.").reveal!

    as(player) do
      click_button "What we know" # the tab comes up once there's something to know
      expect(page).to have_css("#party_knows", text: "Met the king")
    end
  end

  it "moves the players' clock on when the GM passes time, through a new day, from their own table" do
    campaign.set_out!(from_the_setting: true)
    campaign.update!(time_of_day: "night") # so the next part is a new day, which saves the campaign again as the world moves on
    seat(player, rook)
    seat(gm, "gm")
    as(player) { expect(page).to have_css("#table_time", text: /night/i) }

    as(gm) do
      within(".table-controls .gm-tools") { find("[role=tab]", text: "Time").click }
      click_on "A part of the day passes"
    end

    as(player) { expect(page).to have_css("#table_time", text: /day 2/i).and have_css("#table_time", text: /dawn/i) }
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
      # The whisper pops up for a moment, since it's meant for you alone.
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

  # Motion with meaning (docs/DESIGN.md): a replaced panel says what changed in it.
  it "says what changed when a panel is refreshed: HP counts from where it was, a clock's new box pops" do
    clock = campaign.clocks.create!(name: "The tide", segments: 4, public: true)
    seat(gm, "gm")
    as(gm) do
      visit campaign_table_path(campaign)
      wait_for_streams
      # The GM's party panel sits in a side column (folded on this screen): read it wherever it is.
      expect(page).to have_css("#table_party [data-change~=number]", text: rook.stats["max_hp"].to_s, visible: :all)
    end

    rook.update!(hp: 40)
    clock.tick!(2)
    campaign.table_changed

    as(gm) do
      expect(page).to have_css("#table_party [data-change~=number][data-changed-from='#{rook.stats['max_hp']}']", text: "40", visible: :all, wait: 15)
      expect(page).to have_css("#party_knows .clock-dial i.is-new", count: 2, visible: :all, wait: 15)
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
    # The round's order rode the rail, and the round ended with its tally (docs/DESIGN.md, "Motion with meaning").
    as(gm) do
      expect(page).to have_css(".turn-rail .turn-rail__plate", minimum: 2, wait: 15)
      expect(page).to have_css(".round-tally", text: /Round 1 · \w+ dealt \d+/, wait: 15)
    end

    # Fast animations sits in the Menu, outside the battle, and still reaches it.
    as(gm) do
      fast = find("#topbar_menu [data-battle-fast]", visible: :all)
      expect(fast[:"aria-pressed"]).to eq("false")
      execute_script("arguments[0].click()", fast)
      expect(page).to have_css("#topbar_menu [data-battle-fast][aria-pressed=true]", visible: :all)
      expect(page).to have_css("details.gm-controls:not([open])", text: "GM controls")
    end

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
    expect(second.deadline_at).to be_nil # Rook isn't ready yet
    as(player) do
      expect(page).to have_current_path(battle_path(second), wait: 15)
      expect(page).to have_text("The clock starts when Rook is ready", wait: 10)
      click_on "Ready"
      expect(page).to have_css(".countdown[data-controller=countdown]", wait: 10)
      expect(page).to have_no_button("Ready")
    end
    expect(second.reload.deadline_at).to be_present
  end
end
