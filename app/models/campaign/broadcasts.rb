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

  included do
    after_update_commit :broadcast_music, if: :saved_change_to_music?
    after_update_commit :broadcast_time, if: -> { saved_change_to_day? || saved_change_to_time_of_day? }
    after_update_commit :refresh_pages
  end

  # The map, for each audience: players' without hidden places.
  def broadcast_map
    AUDIENCES.each do |gm, stream|
      broadcast_replace_to self, stream, target: "map_canvas", partial: "campaigns/maps/canvas", locals: { campaign: self, gm: gm }
    end
    broadcast_replace_to self, :table, target: "table_here", partial: "campaigns/tables/here", locals: { campaign: self }
  end

  # "The party knows": public clocks, revealed secrets and public flags on
  # the table and the map, for each audience.
  def broadcast_party_knows
    AUDIENCES.each do |gm, stream|
      broadcast_replace_to self, stream, target: "party_knows", partial: "campaigns/tables/party_knows", locals: { campaign: self, gm: gm }
    end
  end

  # Every game page of the campaign changes track with the GM (stage.js);
  # a battle keeps its own.
  def broadcast_music
    Turbo::StreamsChannel.broadcast_action_to(self, :stage, action: :music, target: "stage",
                                              attributes: { follow: music.nil?, url: world.music_path(music).to_s })
  end

  # The party's HP and MP on the table: after a battle, a rest, a potion.
  def broadcast_party
    broadcast_replace_to self, :table, target: "table_party", partial: "campaigns/tables/party", locals: { campaign: self }
  end

  def broadcast_time
    AUDIENCES.each_value { |stream| broadcast_replace_to self, stream, target: "table_time", partial: "campaigns/tables/time", locals: { campaign: self } }
  end

  # The campaign's documents fetch themselves again (debounced: a burst of
  # changes is one refresh).
  def refresh_pages
    broadcast_refresh_later_to self, :pages
  end
end
