# frozen_string_literal: true

# The GM's maps (Map; docs/HANDOFF.md §7, "Maps"): the editor page (show,
# with ?map= the one open), and making, changing (a form, or x, y alone
# from dragging on the parent map) and removing them.
class Campaigns::MapsController < Campaigns::BaseController
  include MapGm

  before_action :require_table_gm
  before_action :set_map, only: %i[edit update destroy]

  def index
    @gm = true
    @maps = @campaign.maps.in_order.includes(:parent)
    @map = @campaign.maps.find_by(id: params[:map]) || @campaign.map_shown || @campaign.root_map
    @scope = MapScope.new(@campaign, use: :editor, gm: true)
  end

  def create
    map = @campaign.maps.new(map_params.reverse_merge(parent_id: params[:parent_id].presence))
    if map.save
      redirect_to campaign_maps_path(@campaign, map: map.id), notice: "#{map.name} is a map now.", status: :see_other
    else
      redirect_to campaign_maps_path(@campaign, map: params[:parent_id]), alert: map.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def edit
    redirect_to campaign_maps_path(@campaign, map: @map.id)
  end

  def update
    @map.image.purge_later if params.dig(:map, :remove_image) == "1"
    saved = @map.update(map_params)
    return head(saved ? :no_content : :unprocessable_content) if request.format.json?

    if saved
      redirect_to campaign_maps_path(@campaign, map: @map.id), notice: "#{@map.name} saved.", status: :see_other
    else
      redirect_to campaign_maps_path(@campaign, map: @map.id), alert: @map.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def destroy
    raise Refusal, "The campaign needs one map at least" if @campaign.maps.count <= 1

    @map.destroy!
    redirect_to campaign_maps_path(@campaign), notice: "#{@map.name} is gone; what was on it is on no map until you put it somewhere.", status: :see_other
  rescue Refusal => e
    redirect_to campaign_maps_path(@campaign, map: @map.id), alert: e.message, status: :see_other
  end

  private

  def set_map
    @map = @campaign.maps.find(params[:id])
  end

  def map_params
    fields = params.expect(map: [ :name, :parent_id, :x, :y, :description, :image ])
    fields[:parent_id] = fields[:parent_id].presence && @campaign.maps.find_by(id: fields[:parent_id])&.id if fields.key?(:parent_id)
    fields.compact_blank.merge(fields.slice(:parent_id, :description))
  end
end
