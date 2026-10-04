# frozen_string_literal: true

# Everything a campaign pushes to the pages open on it, in one place.
#
# The table and the map are live pages where people are typing and the
# dialogue box is mid-line, so they get targeted streams: one element
# replaced, rendered once for the GM and once for the players, so what's
# hidden never reaches a player's browser (the :players and :gm streams;
# Seat#streams says who listens on what).
#
# Everything else is a document (the campaign page, prep, legends): it
# listens on [campaign, :pages] and refreshes, each viewer fetching their
# own page, morphed in place (CampaignPages).
module Campaign::Broadcasts
  extend ActiveSupport::Concern

  AUDIENCES = { false => :players, true => :gm }.freeze

  # What the table shows of the campaign itself: a change to any of these
  # renders its panels again.
  TABLE_FACTS = %w[current_node_id pending_encounter day time_of_day gil lines veils staged_scene_id stage_view shown_map_id].freeze

  included do
    include TableFacts

    after_update_commit :broadcast_music, if: :saved_change_to_music?
    after_update_commit :refresh_pages
    # Counting every save in the transaction (TableFacts): passing time saves
    # the campaign again, after the time, as the world moves on.
    table_facts(TABLE_FACTS) { |changed| table_changed if changed && !previously_new_record? } # a new campaign has no table yet
  end

  # The table's live panels, each rendered once for the GM and once for the
  # players: where the party is, the party's HP, where next, the time, what
  # the party knows, its lines and veils, a dungeon's floorplan while the
  # party is in one, the stage's scene and map (players' without hidden
  # places). Not the dialogue box, the log or the composer.
  TABLE_PANELS = {
    "table_here" => "campaigns/tables/here", "table_party" => "campaigns/tables/party",
    "table_ways" => "campaigns/tables/ways", "table_time" => "campaigns/tables/time", "party_knows" => "campaigns/tables/party_knows",
    "table_floorplan" => "campaigns/tables/floorplan", "table_now" => "campaigns/tables/now", "table_scene" => "campaigns/tables/scene",
    "table_map" => "campaigns/tables/map", "table_limits" => "campaigns/tables/limits"
  }.freeze

  # Something the table shows changed: its panels render again, once for a
  # burst of changes (debounced, like refresh_pages), in a job. The models
  # that matter call this from their commits; callers never pick panels.
  def table_changed
    Turbo::ThreadDebouncer.for("campaign-table-#{id}").debounce { TableRefreshJob.perform_later(self) }
  end

  def broadcast_table
    AUDIENCES.each do |gm, stream|
      TABLE_PANELS.each do |target, partial|
        broadcast_replace_to self, stream, target: target, partial: partial, locals: { campaign: self, gm: gm }
      end
    end
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
