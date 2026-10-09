# frozen_string_literal: true

require "rails_helper"

# A duel as the table sees it (docs/ODA.md): the challenge on the player's
# screen, their answer, and swings on the meter from both seats.
RSpec.describe "A duel", type: :system do
  include_context "a GM's table"

  let!(:ronin) { create_monster(campaign.world, slug: "ronin") }

  def swing_the_meter
    within("[data-controller=duel-meter]") do
      click_on "Swing"
      sleep 0.4 # let the needle travel
      click_on "Stop"
    end
  end

  it "goes from a challenge to three rounds on the meter, and a result" do
    seat(player, rook)
    seat(gm, "gm")
    campaign.challenge!(character: rook, monster: ronin, line: "Draw.")
    as(player) do
      expect(page).to have_css("#table_now", text: "Ronin challenges Rook to a duel!", wait: 15)
      click_on "Accept"
      expect(page).to have_css(".duel-meter", count: 2, wait: 15)
    end
    duel = campaign.reload.current_duel
    as(gm) { expect(page).to have_css("[data-controller=duel-meter] .duel-meter__name", text: "Ronin", wait: 15) }

    3.times do |i|
      as(player) do
        expect(page).to have_css(".duel__round", text: "Round #{i + 1}", wait: 15)
        swing_the_meter
        expect(page).to have_css(".duel-meter.is-swung", text: "Rook", wait: 15)
      end
      as(gm) do
        expect(page).to have_css(".duel__round", text: "Round #{i + 1}", wait: 15)
        swing_the_meter
      end
      # Both in: the round is shown to everyone.
      as(player) { expect(page).to have_css(".duel__card tbody tr", count: i + 1, wait: 15) }
    end

    as(player) { expect(page).to have_css(".duel__result", text: duel.reload.result_line, wait: 15) }
    as(gm) do
      expect(page).to have_css(".duel__card tfoot", text: "Total", wait: 15)
      click_on "Put it away"
      expect(page).to have_no_css(".duel", wait: 15)
    end
  end

  it "marks a coward who refuses" do
    seat(player, rook)
    campaign.challenge!(character: rook, monster: ronin)
    as(player) do
      expect(page).to have_css("#table_now", text: "challenges Rook", wait: 15)
      accept_confirm { click_on "Refuse" }
      expect(page).to have_css("#table_party .coward-mark", text: "Coward", visible: :all, wait: 15)
    end
    expect(rook.reload).to be_coward
  end
end
