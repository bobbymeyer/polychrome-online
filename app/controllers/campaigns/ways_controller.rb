# frozen_string_literal: true

# Where the party goes next (Campaign::Ways). A player suggests a way: it
# goes to the table as a "Where next?" vote with their pick in it. Anyone
# seated can put the question without a pick; the GM can put a wider one
# (scope "map": every place on a map; "places": the ones named), each a
# journey by road. The GM can also just go: from the table, the maps page's
# panel (return_to: "map") or the campaign's page.
class Campaigns::WaysController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign

  def create
    seat = table_seat
    return head(:forbidden) unless seat.seated?

    if seat.gm? && params[:go].present?
      @campaign.take_way!(params[:way])
      return back_to_the_map(notice: "The party is at #{@campaign.reload.current_node&.name}.") if params[:return_to] == "map"
    else
      vote = if seat.gm? && params[:scope] == "map"
        @campaign.ask_where_next!(scope: "map", map: @campaign.maps.find_by(id: params[:map_id]))
      elsif seat.gm? && params[:scope] == "places"
        @campaign.ask_where_next!(scope: "places", places: @campaign.map_nodes.where(id: Array(params[:places])))
      else
        @campaign.ask_where_next!
      end
      vote.picks.find_or_initialize_by(character: seat.character).update!(option: params[:way]) if seat.character? && params[:way].present?
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
