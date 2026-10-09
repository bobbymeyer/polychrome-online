# frozen_string_literal: true

require "rails_helper"

# A duel as the table sees it (docs/ODA.md): the challenge on the player's
# screen, their answer, and an exchange in stances played on the board.
RSpec.describe "A duel", type: :system do
  include_context "a GM's table"

  let!(:ronin) { create_monster(campaign.world, slug: "ronin", tells: { "strike" => [ "Now." ], "guard" => [ "Come, then." ], "feint" => [ "Look there." ] }) }

  it "goes from a challenge on the table to an exchange played on the board" do
    seat(player, rook)
    campaign.challenge!(character: rook, monster: ronin, line: "Draw.")
    as(player) do
      expect(page).to have_css("#table_now", text: "Ronin challenges Rook to a duel!", wait: 15)
      click_on "Accept"
      expect(page).to have_current_path(%r{/battles/\d+}, wait: 15)
      wait_for_streams
      within(".command-panel") { expect(page).to have_button("Strike", wait: 15) }
      expect(page).to have_css(".duel-tell")
      within(".command-panel") { click_on "Guard" }
      # The exchange plays on the board, and the panel comes back for the next one, with its tell.
      within(".command-panel") { expect(page).to have_css(".duel-tell", text: "Exchange 2", wait: 15) }
      expect(page).to have_css(".board[data-status=input]")
    end
    expect(campaign.current_battle.state["duel"]["exchange"]).to eq(2)
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
