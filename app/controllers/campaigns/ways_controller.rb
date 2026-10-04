# frozen_string_literal: true

# Where the party goes next (Campaign::Ways): the GM's call. The GM puts
# the question to the table as a "Where next?" vote, or a wider one (scope
# "map": every place on a map; "places": the ones named), each a journey by
# road; players answer in the vote, and don't see the ways before it. The
# GM can also just go: from the table, the maps page's panel (return_to:
# "map") or the campaign's page.
class Campaigns::WaysController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign

  def create
    return head(:forbidden) unless table_seat.gm?

    if params[:go].present?
      @campaign.take_way!(params[:way])
      return back_to_the_map(notice: "The party is at #{@campaign.reload.current_node&.name}.") if params[:return_to] == "map"
    else
      case params[:scope]
      when "map" then @campaign.ask_where_next!(scope: "map", map: @campaign.maps.find_by(id: params[:map_id]))
      when "places" then @campaign.ask_where_next!(scope: "places", places: @campaign.map_nodes.where(id: Array(params[:places])))
      else @campaign.ask_where_next!
      end
    end
    redirect_back_or_to campaign_table_path(@campaign), status: :see_other
  rescue Refusal, ActiveRecord::RecordInvalid => e
    return back_to_the_map(alert: e.message) if params[:return_to] == "map"

    redirect_back_or_to campaign_table_path(@campaign), alert: e.message, status: :see_other
  end

  private

  def back_to_the_map(notice: nil, alert: nil)
    flash[:map_notice] = notice if notice
    flash[:map_alert] = alert if alert
    redirect_to campaign_map_panel_path(@campaign), status: :see_other
  end
end
