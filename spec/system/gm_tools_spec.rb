# frozen_string_literal: true

require "rails_helper"

# The GM's side of the table: the tools beside the play, one tab at a time
# and remembered; the log pinned open as a column; and a way on that asks
# first when it's a dangerous road.
RSpec.describe "The GM's tools at the table", type: :system do
  let(:gm) { make_user("Gamemaster") }
  let(:campaign) { create_campaign.tap { |c| c.update!(gm_id: gm.id) } }
  let!(:rook) { create_character(campaign, name: "Rook") }

  it "shows one tool at a time, beside the play, and keeps the one the GM had open" do
    campaign.clocks.create!(name: "The tide comes in", segments: 4)
    seat(gm, "gm")

    as(gm) do
      within(".table-controls .gm-tools") do
        expect(page).to have_css("[role=tab][aria-selected=true]", text: "Scenes")
        expect(page).to have_css("[role=tab]", text: /Clocks\s*1/) # one running
        expect(page).to have_no_text("The tide comes in")
        find("[role=tab]", text: "Clocks").click
        expect(page).to have_text("The tide comes in")
      end

      visit current_path
      within(".gm-tools") do
        expect(page).to have_css("[role=tab][aria-selected=true]", text: "Clocks")
        expect(page).to have_text("The tide comes in")
        expect(page).to have_no_css("#gm_panel_scenes", visible: true)
      end
    end
  end

  it "shows the moves that are live when the Moves tab is opened, and makes one so" do
    campaign.world.generator_tables.where(kind: "complications").destroy_all
    campaign.world.generator_tables.create!(name: "Moves", slug: "moves_system", kind: "complications", entries: [ { "text" => "Somebody's watching." } ])
    seat(gm, "gm")

    as(gm) do
      within(".table-controls .gm-tools") do
        find("[role=tab]", text: "Moves").click
        within("#gm_moves") do
          expect(page).to have_text("“Somebody's watching.”")
          click_on "Say it"
        end
      end
      expect(page).to logged?("Somebody's watching.")
      expect(page).to have_css("#gm_moves", text: "Somebody's watching.") # the panel is still there, fetched again
    end
  end

  it "opens a tool from the Now line, and folds the tools away while the table is busy" do
    seat(gm, "gm")
    as(gm) do
      within("#table_now") { click_on "Call a check" }
      expect(page).to have_css("#gm_panel_check", visible: true, text: "Who tries")

      wait_for_streams
      Message.choice(campaign, options: [ "Trust Cid", "Refuse" ]).save!
      expect(page).to have_css("#table_now[data-state=choice]")
      expect(page).to have_link("Settle it ↓")
      visit current_path # a fresh look, as the GM would have it mid-vote
      expect(page).to have_no_css(".gm-tools__tabs", visible: true)
      click_on "Tools"
      expect(page).to have_css(".gm-tools__tabs", visible: true)
    end
  end

  it "pins the log open beside the page, and it stays pinned" do
    seat(gm, "gm")
    as(gm) do
      expect(page).to have_no_css(".log-drawer.is-docked") # 1280 wide: not pinned until asked
      find(".log-drawer__tab").click
      within(".log-drawer__panel") { click_on "Pin" }
      expect(page).to have_css(".log-drawer.is-docked")
      expect(page).to have_css("html.log-docked", visible: :all)

      visit current_path
      expect(page).to have_css(".log-drawer.is-docked .log-drawer__panel", visible: true)
      within(".log-drawer__panel") { click_on "Unpin" }
      expect(page).to have_no_css(".log-drawer.is-open")
    end
  end

  it "asks before going straight down a dangerous road" do
    here = campaign.map_nodes.create!(name: "Varn", x: 100, y: 100, visible: true)
    there = campaign.map_nodes.create!(name: "The Old Ruins", x: 300, y: 100, visible: true)
    campaign.map_edges.create!(from_node: here, to_node: there, state: "dangerous")
    campaign.update!(current_node: here)
    seat(gm, "gm")

    as(gm) do
      # The ways show once the GM calls travel (Campaign::Controls), for everyone.
      expect(page).to have_no_button("To The Old Ruins (by a dangerous road)")
      click_on "Travel"
      dismiss_confirm(/The road to The Old Ruins is dangerous/) { click_on "To The Old Ruins (by a dangerous road)" }
      expect(campaign.reload.current_node).to eq(here)
      accept_confirm { click_on "To The Old Ruins (by a dangerous road)" }
      expect(page).to have_text("The party is at The Old Ruins").or have_css("#table_ways", text: "Varn")
      expect(campaign.reload.current_node).to eq(there)
    end
  end
end
