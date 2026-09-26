# frozen_string_literal: true

# Map editing and travel are the GM's (§7): only the table's GM seat may.
module MapGm
  extend ActiveSupport::Concern
  include TableSeat

  private

  def require_gm
    head :forbidden unless table_gm?(@campaign)
  end

  def panel(notice: nil, alert: nil)
    flash[:map_notice] = notice if notice
    flash[:map_alert] = alert if alert
    redirect_to campaign_map_panel_path(@campaign), status: :see_other
  end
end
