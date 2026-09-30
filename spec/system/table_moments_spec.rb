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
      within("#table_choice") { click_on "Trust Cid" }
    end
    as(gm) do
      within("#table_choice") do
        expect(page).to have_css(".choice__option", text: /Trust Cid.*Rook/m)
        accept_confirm { find(".choice__option", text: "Trust Cid").click_on("Settle on this") }
      end
    end

    as(player) { expect(page).to have_no_css("#table_choice .choice") }
    expect(campaign.flags.find_by!(key: "trusted_cid").value).to eq("Trust Cid")
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
      find("summary", text: "Call for a check").click
      check "Rook"
      select "Agi", from: "check_stat"
      fill_in "check_reason", with: "scale the wall"
      click_on "Roll"
    end

    [ gm, player ].each { |person| as(person) { expect(page).to logged?(/Rook: .*check.* to scale the wall\. \d+% · rolled \d+/) } }
  end

  it "shows the players the road as the party travels it, and not before" do
    village = campaign.map_nodes.create!(name: "Varn", x: 100, y: 100, visible: true)
    ruins = campaign.map_nodes.create!(name: "The Old Ruins", x: 300, y: 100, visible: false)
    road = campaign.map_edges.create!(from_node: village, to_node: ruins)
    campaign.update!(current_node: village)
    seat(player, rook)
    as(player) do
      visit campaign_map_path(campaign)
      wait_for_streams
      expect(page).to have_no_css("#map_canvas", text: "The Old Ruins")
    end

    campaign.travel!(road)

    as(player) do
      expect(page).to have_css("#map_canvas", text: "The Old Ruins")
      expect(find("#map_canvas svg")["aria-label"]).to end_with("the party is at The Old Ruins")
    end
  end

  it "plays around one shared screen, with a phone joining as a controller" do
    seat(gm, "gm")
    as(gm) do
      visit campaign_table_path(campaign, view: "screen")
      wait_for_streams
      expect(page).to have_css(".coop-join__qr svg")
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
