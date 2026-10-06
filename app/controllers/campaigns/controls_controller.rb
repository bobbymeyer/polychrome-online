# frozen_string_literal: true

# The GM calls what kind of moment the table is in (Campaign::Controls):
# talk, travel, or things to do here. Everyone's table follows.
class Campaigns::ControlsController < Campaigns::BaseController
  before_action :require_table_gm

  def update
    @campaign.call_controls!(params[:kind].to_s)
    # Back to the table: the GM's own page is morphed at once, everyone else's follows by refresh (Campaign::Broadcasts).
    redirect_back_or_to campaign_table_path(@campaign), status: :see_other
  end
end
