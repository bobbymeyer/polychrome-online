# frozen_string_literal: true

require "rails_helper"

# The table as several people see it at once, each in their own browser:
# what reaches whom, live, without a reload.
RSpec.describe "The live table", type: :system do
  let(:gm) { make_user("Gamemaster") }
  let(:player) { make_user("Player") }
  let(:campaign) { create_campaign.tap { |c| c.update!(gm_id: gm.id) } }
  let!(:rook) { create_character(campaign, name: "Rook", user: player) }

  it "tells the players what the party is asking, and what it found out goes to the log and Legends" do
    seat(player, rook)
    as(player) { expect(page).to have_no_button("What we know") } # nothing to know yet: no tab for it

    campaign.secrets.create!(body: "Met the king.").reveal!
    chain = campaign.secrets.create!(body: "The mayor pays the goblins.", key: "lamp", steps: "Why is the lamp lit at midnight?\nSomeone leaves before dawn.")
    chain.find_clue!

    as(player) do
      expect(page).to logged?("Met the king") # said once, as it came out
      click_button "What we know" # the tab comes up for what the party is asking
      expect(page).to have_css("#party_knows", text: "Why is the lamp lit at midnight?")
      expect(page).to have_no_css("#party_knows", text: "Met the king") # found out for good: Legends', not the table's
      within("#party_knows") { click_on "Legends" }
      expect(page).to have_css("h2", text: "What they found out")
      expect(page).to have_text("Met the king.")
    end
  end

  it "moves the players' clock on when the GM passes time, through a new day, from their own table" do
    campaign.set_out!(from_the_setting: true)
    campaign.update!(time_of_day: "night") # so the next part is a new day, which saves the campaign again as the world moves on
    seat(player, rook)
    seat(gm, "gm")
    as(player) { expect(page).to have_css("#table_time", text: /night/i) }

    as(gm) do
      within("#table_now") { click_on "Things to do here" } # time passes where the day is spent
      within("#table_ways") { click_on "A part of the day passes" }
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
      # The tally sits right over the roster band, however many rows it has (board.js seats it).
      gap = page.evaluate_script("document.querySelector('.roster').getBoundingClientRect().top - document.querySelector('.round-tally').getBoundingClientRect().bottom")
      expect(gap.abs).to be < 2
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

  it "plays a long line on the stage in pages, and puts the box away when dismissed" do
    marga = campaign.npcs.create!(name: "Old Marga")
    seat(player, rook)
    long = "Hold on! The bridge is out past the mill, and the river's up. You'll want the ford at Ashby, two days east, " \
           "unless someone here can swim against a current like that. I wouldn't. Nobody would. Not after what happened " \
           "to the miller's boy last spring, God rest him. So, the ford. Or the ferryman, if you've coin and patience."

    as(player) do
      page.driver.browser.manage.window.resize_to(1400, 1000)
      campaign.messages.create!(body: long, speaker: marga)
      box = find("#stage .dialogue")
      expect(box).to have_css(".dialogue__body", text: /\AHold on!/)
      expect(box).to have_no_css(".dialogue__body", text: /patience\.\z/) # the first page only
      box.click while box.has_no_css?(".dialogue__body", text: /patience\.\z/, wait: 0.5) # on through the pages
      expect(box).to have_no_css(".dialogue__body", text: /\AHold on!/)

      find("#stage .dialogue__close").click
      expect(page).to have_no_css("#stage .dialogue")
      campaign.messages.create!(body: "Well? Off with you.")
      expect(page).to have_css("#stage .dialogue", text: "Off with you")
    end
  end
  it "is three views on a phone: you and the party, the stage, the log, picked from a strip under the top bar" do
    marga = campaign.npcs.create!(name: "Old Marga")
    seat(player, rook)

    as(player) do
      page.driver.browser.manage.window.resize_to(390, 844)
      visit campaign_table_path(campaign)
      expect(page).to have_css(".table-views", visible: true)
      expect(page).to have_css(".table-views__tab[aria-current=page]", text: "Stage") # the stage first
      expect(page).to have_css("#stage", visible: true)
      expect(page).to have_no_css(".player-card", visible: true)
      expect(page).to have_no_css(".log-drawer__tab", visible: true) # the log is a view here, not a drawer

      click_on "You & party"
      expect(page).to have_css(".player-card", visible: true, text: "Rook")
      expect(page).to have_no_css("#stage", visible: true)

      wait_for_streams
      campaign.messages.create!(body: "The bridge is out.", speaker: marga)
      expect(page).to have_css(".table-views__badge", visible: true, text: "1") # a line you haven't seen
      click_on "Log"
      expect(page).to have_css("#log_drawer", visible: true, text: "The bridge is out.")
      expect(page).to have_no_css(".table-views__badge", visible: true)
      expect(page).to have_no_css(".player-card", visible: true)

      visit current_path # the view you were on is kept
      expect(page).to have_css(".table-views__tab[aria-current=page]", text: "Log")
      page.driver.browser.manage.window.resize_to(1400, 1000)
    end
  end
  it "lets the GM speak as the scene's speaker, by chip or by name, and whisper from the party panel" do
    cid = campaign.npcs.create!(name: "Cid", title: "Engineer")
    scene = campaign.scenes.create!(name: "Ambush", script: "Cid (angry): Behind you!\nNarrator: Silence.")
    seat(gm, "gm")
    seat(player, rook)

    as(gm) do
      within("#composer") { expect(page).to have_css(".composer__chip[aria-pressed=true]", text: "Narrator") }
      wait_for_streams
      scene.reload.start!
      # The scene moved: the empty box fetches itself again, and Cid, speaking on the stage, is pressed.
      within("#composer") { expect(page).to have_css(".composer__chip[aria-pressed=true]", text: "Cid") }
      fill_in "message_body", with: "Hand me that wrench."
      click_on "Send"
      expect(page).to logged?("Hand me that wrench.")
      expect(campaign.messages.last.speaker).to eq(cid)

      # A name and a colon speaks as them, whoever is pressed.
      fill_in "message_body", with: "Narrator: The lamp gutters."
      click_on "Send"
      expect(page).to logged?("The lamp gutters.")
      expect(campaign.messages.last.speaker).to be_nil

      # A whisper starts at the person: the box says who hears.
      within("#table_party") { click_on "Whisper" }
      within("#composer") do
        expect(page).to have_css(".composer__whispering", visible: true, text: "Whispering to Rook")
        fill_in "message_body", with: "You feel watched."
        click_on "Send"
        expect(page).to have_no_css(".composer__whispering", visible: true) # one line: the next goes to everyone
      end
      expect(campaign.messages.last).to have_attributes(scope: "whisper", recipient: rook, body: "You feel watched.")
    end
    as(player) { expect(page).to have_css(".toast", text: "You feel watched.") }
  end
end
