# frozen_string_literal: true

# Map editing is the GM's (§7): only the table's GM seat may
# (TableSeat#require_table_gm), and it answers in the map's panel.
module MapGm
  extend ActiveSupport::Concern
  include TableSeat

  private

  def panel(notice: nil, alert: nil)
    flash[:map_notice] = notice if notice
    flash[:map_alert] = alert if alert
    redirect_to campaign_map_panel_path(@campaign), status: :see_other
  end
end
