# frozen_string_literal: true

require "rails_helper"

# The GM's side of the table: the tools beside the play, one tab at a time
# and remembered; the log pinned open as a column; and a way on that asks
# first when it's a dangerous road.
RSpec.describe "The GM's tools at the table", type: :system do
  include_context "a GM's table"

  it "keeps the rest of the tools behind Tools, one at a time, and keeps the one the GM had open" do
    campaign.clocks.create!(name: "The tide comes in", segments: 4)
    seat(gm, "gm")

    as(gm) do
      expect(page).to have_no_css(".gm-tools") # not until called, like the other controls
      within("#table_now") { click_on "GM", exact: true } # on the strip, after Fight
      within("#table_called .gm-tools") do
        expect(page).to have_css("[role=tab]", count: 2) # Moves and More: clocks, secrets and time left the table
        expect(page).to have_css("[role=tab][aria-selected=true]", text: "Moves")
        expect(page).to have_no_text("The tide comes in")
        find("[role=tab]", text: "More").click
        expect(page).to have_text("Grant an archetype")
      end

      visit current_path
      within("#table_now") { click_on "GM", exact: true }
      within(".gm-tools") do
        expect(page).to have_css("[role=tab][aria-selected=true]", text: "More")
        expect(page).to have_no_css("#gm_panel_moves", visible: true)
      end
    end
  end

  it "shows the moves that are live when the Moves tab is opened, and makes one so" do
    campaign.world.generator_tables.where(kind: "complications").destroy_all
    campaign.world.generator_tables.create!(name: "Moves", slug: "moves_system", kind: "complications", entries: [ { "text" => "Somebody's watching." } ])
    seat(gm, "gm")

    as(gm) do
      within("#table_now") { click_on "GM", exact: true } # a control: the page comes back, and its streams with it
      expect(page).to have_css("#table_now .controls-call [aria-pressed=true]", text: "GM") # the new page, not the old one's streams
      wait_for_streams
      within("#table_called .gm-tools") do
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

  it "calls a check or a scene from the Now line, and that tool comes to the table" do
    seat(gm, "gm")
    as(gm) do
      expect(page).to have_no_css("#table_called", visible: true)
      within("#table_now") { click_on "Check" }
      expect(page).to have_css("#table_called", visible: true, text: "Who tries")
      within("#table_now") { click_on "Scene" }
      expect(page).to have_css("#table_called", visible: true, text: "No scenes yet")
      expect(page).to have_no_text("Who tries")

      wait_for_streams
      Message.choice(campaign, options: [ "Trust Cid", "Refuse" ]).save!
      expect(page).to have_css("#table_now[data-state=choice]")
      expect(page).to have_link("Settle it ↓")
      expect(page).to have_no_css("#table_now .controls-call") # the vote comes first
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
      click_on "Move", exact: true
      dismiss_confirm(/The road to The Old Ruins is dangerous/) { click_on "To The Old Ruins (by a dangerous road)" }
      expect(campaign.reload.current_node).to eq(here)
      accept_confirm { click_on "To The Old Ruins (by a dangerous road)" }
      expect(page).to have_text("The party is at The Old Ruins").or have_css("#table_ways", text: "Varn")
      expect(campaign.reload.current_node).to eq(there)
    end
  end
  it "asks from the map: calling Travel puts it on the stage, a place pressed offers Go and Ask the table" do
    here = campaign.map_nodes.create!(name: "Varn", x: 300, y: 300, visible: true)
    there = campaign.map_nodes.create!(name: "Far Hold", x: 900, y: 300, visible: true)
    campaign.map_edges.create!(from_node: here, to_node: there, state: "open", duration: 2)
    campaign.update!(current_node: here)
    seat(gm, "gm")

    as(gm) do
      expect(page).to have_css("#stage .table-time__view", text: /map/i) # the stage is the switch
      expect(page).to have_no_css("#table_map .map-sheet")
      within("#table_now") { click_on "Move", exact: true }
      expect(page).to have_css("#table_map .map-sheet[data-controller=map-ask]", visible: true)
      expect(page).to have_css("#stage .table-time__view", text: /place/i)
      # The party's flag stands on the party's place, not scaled away from it (stage.css): the flag's tip (the
      # path's origin) and the place's own point, both as the sheet renders them (through the same matrices, so
      # the stage settling, the place's pulse and the flag's bob don't move the mark).
      # Measured once the table's refresh after Travel has landed and the marker's hop has played (change_controller):
      # the mark is where the flag settles, not where it is mid-hop.
      mark = -> do
        page.evaluate_script(<<~JS)
          (() => {
            const path = document.querySelector("#table_map .map-party__flag path"), node = document.querySelector("#table_map .map-node.is-party")
            const tip = new DOMPoint(0, 0).matrixTransform(path.getScreenCTM()), at = new DOMPoint(0, 0).matrixTransform(node.getScreenCTM())
            return [tip.x - at.x, tip.y - at.y]
          })()
        JS
      end
      settled = ->(dx, dy) { dx.abs < 2 && dy.between?(-40, 0) } # its tip on the place's line, a little above it, bobbing
      dx, dy = mark.call
      10.times { break if settled.call(dx, dy); sleep 0.3; dx, dy = mark.call }
      expect(settled.call(dx, dy)).to be(true), "the flag sits #{dx.round(1)}px across and #{dy.round(1)}px above the place"

      find("a.map-node__ask[data-node-name='Far Hold']").click
      within(".map-ask") do
        expect(page).to have_text("Far Hold 2 parts of a day")
        expect(page).to have_button("Go").and have_button("Ask the table")
        click_on "Ask the table"
      end
      expect(page).to have_css("#table_choice .choice", text: "To Far Hold (2 parts of a day)")
      expect(campaign.open_choice.options).to eq([ "To Far Hold (2 parts of a day)", Campaign::STAY ])

      find("#stage .table-time__view", text: /place/i).click # the switch again: the place comes back
      expect(page).to have_css("#stage .table-time__view", text: /map/i)
      expect(page).to have_no_css("#table_map .map-sheet", visible: true)
    end
  end
end
