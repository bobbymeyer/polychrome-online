# frozen_string_literal: true

# Everything a campaign pushes to the pages open on it, in one place.
#
# Pages refresh: each viewer fetches their own page again, as their own
# seat, and it's morphed in place, so what's hidden never reaches a player's
# browser. Whoever made the change sees it through their own action, which
# redirects back (or, for a line sent from the talk box, says to refresh). The table listens on [campaign, :table_refresh] (only the table:
# a battle page hears [campaign, :table] too, and mustn't reload mid-fight);
# what's alive on it, the dialogue box mid-line, the log, a half-typed line,
# is kept through the morph (data-turbo-permanent). The documents (the
# campaign page, prep, legends) listen on [campaign, :pages].
#
# Lines said, whispers and what only the GM is asked (the :table, :gm and
# :whispers streams; Seat#streams says who listens on what) still arrive as
# targeted streams: they're added to the log as they come.
module Campaign::Broadcasts
  extend ActiveSupport::Concern

  # What the table shows of the campaign itself: a change to any of these
  # renders its panels again.
  TABLE_FACTS = %w[current_node_id pending_encounter day time_of_day gil lines veils staged_scene_id stage_view shown_map_id controls].freeze

  # What no page shows: where the dice got to (Campaign#roll), and the count
  # of visits (Campaign::Moment). A save that moves only these refreshes nothing.
  UNSHOWN = %w[rng visits updated_at].freeze

  included do
    include TableFacts

    after_update_commit :broadcast_music, if: :saved_change_to_music?
    # Counting every save in the transaction, as TableFacts does: a roll
    # after the change that matters still saves only the dice last.
    after_save { @pages_changed = true if (saved_changes.keys - UNSHOWN).any? }
    after_rollback { @pages_changed = false }
    after_update_commit :refresh_pages, if: :pages_changed?
    # Counting every save in the transaction (TableFacts): passing time saves
    # the campaign again, after the time, as the world moves on.
    table_facts(TABLE_FACTS) { |changed| table_changed if changed && !previously_new_record? } # a new campaign has no table yet
  end

  # Whether anything a page shows changed since the transaction began; asked once, at the commit.
  def pages_changed?
    changed = @pages_changed == true
    @pages_changed = false
    changed
  end

  # Something the table shows changed: every table open on the campaign
  # fetches itself again, once for a burst of changes (debounced). The
  # browser whose request made the change already has it (the action
  # redirects back to the table, morphed the same way), so this refresh
  # carries that request's id and that browser lets it go.
  def table_changed
    broadcast_refresh_later_to self, :table_refresh
  end

  # Every game page of the campaign changes track with the GM (stage.js);
  # a battle keeps its own.
  # A music step can cut instead of crossfading (Beat#transition); set just before the change.
  attr_accessor :music_cut

  def broadcast_music
    Turbo::StreamsChannel.broadcast_action_to(self, :stage, action: :music, target: "stage",
                                              attributes: { follow: music.nil?, url: world.music_path(music).to_s, cut: music_cut == true })
  end

  # The campaign's documents fetch themselves again (debounced: a burst of
  # changes is one refresh).
  def refresh_pages
    broadcast_refresh_later_to self, :pages
  end
end
