# frozen_string_literal: true

require "rails_helper"

# The moments of a session that happen to everyone at once: a choice put
# to the party, a check the GM calls, the road on the map, and the table
# played around one shared screen with phones as controllers.
RSpec.describe "Moments at the table", type: :system do
  let(:gm) { make_user("Gamemaster") }
  let(:player) { make_user("Player") }
  let(:campaign) { create_campaign.tap { |c| c.update!(gm_id: gm.id) } }
  let!(:rook) { create_character(campaign, name: "Rook", user: player) }

  it "puts a choice to the party: the player picks, the GM sees it and settles it" do
    seat(gm, "gm")
    seat(player, rook)

    Message.choice(campaign, options: [ "Trust Cid", "Refuse" ], flag: "trusted_cid").save!

    as(player) do
      expect(page).to have_css("#table_choice .choice", visible: true)
      within("#table_choice") do
        # The options are rows of a table: a click anywhere on the row picks it (pick_table_controller).
        find(".choice__option", text: "Refuse").find("td.pick-row__cost").click
        expect(page).to have_css(".choice__option.is-mine", text: "Refuse")
        # Up and Down walk the rows; Enter picks the one in focus.
        find(".choice__option.is-mine .pick-row__act").send_keys(:arrow_up, :enter)
        expect(page).to have_css(".choice__option.is-mine", text: "Trust Cid")
        expect(page).to have_css(".is-mine .choice__mine", text: /your pick/i)
        expect(page).to have_no_css(".choice__option.is-mine", text: "Refuse")
      end
    end
    as(gm) do
      within("#table_choice") do
        expect(page).to have_css(".choice__option", text: /Trust Cid.*Rook/m)
        expect(page).to have_no_css(".is-mine") # the GM didn't pick
        accept_confirm { find(".choice__option", text: "Trust Cid").click_on("Settle on this") }
      end
    end

    as(player) { expect(page).to have_no_css("#table_choice .choice") }
    expect(campaign.flags.find_by!(key: "trusted_cid").value).to eq("Trust Cid")
  end

  it "shows a player what they can do now: tabs for what they look up, and a battle takes their moves" do
    seat(player, rook)
    as(player) do
      expect(page).to have_css(".your-moves", visible: true)
      expect(page).to have_css("#table_party", visible: true, text: "Rook") # 1280 wide: the party starts open in the column
      expect(page).to have_no_button("What we know") # nothing to know yet: no tab for it
      click_button "Party"
      expect(page).to have_no_css("#table_party", visible: true) # pressing the open one closes it
      click_button "Party"
      expect(page).to have_css("#table_party", visible: true, text: "Rook")
      expect(page).to have_css("#stage #table_map[hidden]", visible: :all) # the map waits until the GM shows it
      find("details.talk summary", text: "Say something").click
      expect(page).to have_css("#composer textarea", visible: true)

      wait_for_streams
      rook.update!(hp: 0)
      # The tab says so without opening it (its ::after, from the party panel it hides).
      page.document.synchronize do
        badge = page.evaluate_script(%(getComputedStyle(document.querySelector(".drawers__tab--party"), "::after").content))
        raise Capybara::ExpectationNotMet, badge unless badge.include?("down")
      end
      start_battle(campaign: campaign)
      expect(page).to have_css("#table_now[data-state=battle]")
      expect(page).to have_no_css(".your-moves", visible: true)
    end
  end

  it "lays a wide screen out in three columns: you and the party, the stage over the controls, the log" do
    seat(player, rook)
    as(player) do
      expect(page).to have_css(".table__side .player-card", text: "Rook", visible: true) # 1280 wide: you on the left
      expect(page).to have_css("#drawer_party", visible: true) # the party starts open under you; the map is on the stage
      expect(page).to have_css(".table__stage #stage", visible: true)
      expect(page).to have_css(".table__stage .table-controls #table_now", visible: true) # the controls under the stage
      expect(page).to have_css(".table-controls .your-moves", visible: true)
      expect(page).to have_css(".log-drawer.is-docked") # and the log on the right
      expect(page).to have_css(".topbar__seat", text: "At the table as Rook", visible: :all) # in the account menu
      side = page.evaluate_script("document.querySelector('.table__side').getBoundingClientRect().right")
      stage = page.evaluate_script("document.querySelector('.table__stage').getBoundingClientRect().left")
      expect(side).to be <= stage
    end
  end

  it "keeps the player's own HP up top in step with the party panel" do
    seat(player, rook)
    as(player) do
      expect(page).to have_css(".player-card", text: "Rook")
      wait_for_streams
      rook.update!(hp: 7)
      expect(page).to have_css(".table-you .vitals strong", text: /\A7\z/)
    end
  end

  it "stops the table for a deadline and an awakening: one card at a time, up over everything, then put away" do
    seat(player, rook)
    clock = campaign.clocks.create!(name: "The tide", segments: 2, public: true, full_line: "The tide comes in over the platforms.")
    clock.tick!(2)
    as(player) do
      within("dialog.deadline-stage[open]") { expect(page).to have_text("The tide comes in over the platforms.") }
      find("dialog.deadline-stage[open]").click
      expect(page).to have_no_css("dialog.deadline-stage[open]")
    end

    monk = create_job(campaign.world, slug: "monk")
    campaign.grant_job!(monk, to: rook, line: "I remember my fists.")
    as(player) do
      within("dialog.awakening-stage[open]") do
        expect(page).to have_text("ROOK AWAKENS").or have_text("Rook awakens")
        expect(page).to have_text("I remember my fists.")
        expect(page).to have_css(".awakening-card.is-turned")
      end
      find("dialog.awakening-stage[open]").click # put away: seen
    end

    # A page that comes up just after shows the card it missed, once.
    as(player) do
      visit campaign_table_path(campaign)
      expect(page).to have_no_css("dialog.awakening-stage[open]") # this browser saw it already
    end
    as(gm) do # the GM, who set it off from another page, comes to the table after
      sign_in_through_the_page(gm)
      visit campaign_table_path(campaign)
      expect(page).to have_css("dialog.awakening-stage[open]", text: /awakens/i)
    end
  end

  it "rolls a check the GM calls, for everyone to see" do
    seat(player, rook)
    seat(gm, "gm")

    as(gm) do
      within("#table_now") { click_on "Check" } # the GM calls it (Campaign::Controls); the form comes to the table
      check "Rook"
      select "Athletics", from: "check_stat"
      fill_in "check_reason", with: "scale the wall"
      click_on "Roll"
    end

    # The die lands, then the modifier (Rook's Str above typical) moves it, for everyone.
    as(player) { expect(page).to have_css(".check-moment .check-moment__step", text: /\+\d+ Str/, wait: 6) }
    [ gm, player ].each { |person| as(person) { expect(page).to logged?(/Rook: Athletics check \(normal\) to scale the wall\. needed 51 or over · rolled \d+ \+\d+ Str = \d+/) } }
  end

  it "shows the players the road as the party travels it, and not before" do
    village = campaign.map_nodes.create!(name: "Varn", x: 100, y: 100, visible: true)
    ruins = campaign.map_nodes.create!(name: "The Old Ruins", x: 300, y: 100, visible: false)
    road = campaign.map_edges.create!(from_node: village, to_node: ruins)
    campaign.update!(current_node: village)
    campaign.show_map!
    seat(player, rook)
    as(player) do
      visit campaign_table_path(campaign)
      wait_for_streams
      expect(page).to have_css("#table_map", text: "Varn")
      expect(page).to have_no_css("#table_map", text: "The Old Ruins")
    end

    campaign.travel!(road)

    as(player) do
      expect(page).to have_css("#table_map", text: "The Old Ruins")
      expect(find("#table_map svg")["aria-label"]).to end_with("the party is at The Old Ruins")
    end
  end

  it "plays around one shared screen, with a phone joining as a controller" do
    seat(gm, "gm")
    as(gm) do
      # The way in is in the GM's tools, to hold up or read out; the screen itself is only the show.
      within(".table-controls .gm-tools") { click_on "Tools"; find("[role=tab]", text: "More").click }
      expect(page).to have_css("#gm_panel_more .coop-join__qr svg", visible: true)
      visit campaign_table_path(campaign, view: "screen")
      wait_for_streams
      expect(page).to have_no_css(".coop-join")
      expect(page).to have_no_field("message[body]") # the screen has no composer
    end

    lenna = create_character(campaign, name: "Lenna") # nobody's yet
    Capybara.using_session("phone") do
      visit join_path(campaign.reload.join_code, view: "controller") # the shared screen's QR code
      fill_in "Your name", with: "Sam"
      click_on "Lenna"
      expect(page).to have_css(".vitals", text: "HP")
      expect(page).to have_css("h1", text: "Lenna")
      wait_for_streams
    end
    expect(lenna.reload.user.name).to eq("Sam")

    campaign.messages.create!(body: "Psst, Lenna.", scope: "whisper", recipient: lenna)
    campaign.narrate("The lanterns go out.")

    Capybara.using_session("phone") { expect(page).to logged?("Psst, Lenna").and logged?("The lanterns go out") }
    as(gm) do
      expect(page).to logged?("The lanterns go out")
      expect(page).not_to logged?("Psst, Lenna") # the screen shows what everyone may see
    end
  end
end
