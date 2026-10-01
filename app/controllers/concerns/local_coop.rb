# frozen_string_literal: true

# Local co-op (docs/DESIGN.md, "Local co-op"): one shared screen everyone
# watches (a TV at the table, or a stream on Discord), and phones as
# controllers. The same table and battle pages serve both, in a view:
#
#   screen     — the show: map, dialogue, board, choices and checks, big;
#                no menus, and a QR code to join
#   controller — your part: your character, your commands, your picks;
#                the show itself stays on the screen
#   stage      — nothing but the Stage (docs/DESIGN.md, "The Stage"): for a
#                TV or a stream where the table is played out loud, with no
#                menus, log or panels around it
#
# A view is picked with ?view=screen|controller (off to leave) and kept for
# the campaign in this browser's session, so it survives the jump into a
# battle and back.
module LocalCoop
  extend ActiveSupport::Concern

  VIEWS = %w[screen controller stage].freeze
  # The views for everyone to watch: a spectator's seat, whoever is signed in on the device.
  WATCHED = %w[screen stage].freeze

  included do
    helper_method :coop_view
  end

  private

  def coop_view(campaign = @campaign)
    return unless campaign

    views = session[:coop_views] || {}
    views[campaign.id.to_s]
  end

  def remember_coop_view(campaign)
    return unless params.key?(:view)

    views = (session[:coop_views] || {}).dup
    if VIEWS.include?(params[:view])
      views[campaign.id.to_s] = params[:view]
    else
      views.delete(campaign.id.to_s)
    end
    session[:coop_views] = views
  end
end
