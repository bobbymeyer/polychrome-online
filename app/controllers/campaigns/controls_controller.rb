# frozen_string_literal: true

# The GM calls what kind of moment the table is in (Campaign::Controls):
# talk, travel, or things to do here. Everyone's panels follow.
class Campaigns::ControlsController < Campaigns::BaseController
  before_action :require_table_gm

  def update
    @campaign.call_controls!(params[:kind].to_s)
    respond_to do |format|
      # The GM's own screen repaints its panels at once, in place: no reload, and no gap in what it hears while
      # one. Everyone else's follow by broadcast (Campaign::Broadcasts), the GM's again a moment later, the same.
      format.turbo_stream { render turbo_stream: table_panels_for(gm: true) }
      format.html { redirect_back_or_to campaign_table_path(@campaign), status: :see_other }
    end
  end

  private

  def table_panels_for(gm:)
    Campaign::Broadcasts::TABLE_PANELS.map do |target, partial|
      turbo_stream.replace(target, partial: partial, locals: { campaign: @campaign, gm: gm })
    end
  end
end
