# frozen_string_literal: true

# Asking the language model for suggestions (Draft), keeping one, or
# throwing them away. Prep drafts belong to a campaign and are the GM's;
# world-building drafts belong to a world and are its editors'.
class DraftsController < ApplicationController
  include TableSeat

  before_action :set_owner
  before_action :set_draft, only: %i[keep destroy]

  def create
    kind = params.expect(:kind)
    return back(alert: "Pick something to suggest") unless Draft::KINDS.include?(kind)
    return back(alert: "No language model is set up (LLM_URL)") unless Llm.enabled?

    target = find_target(kind)
    Draft.start!(@owner, kind, params.fetch(:draft, {}).permit(:idea, :pitch, :root, :shape, :type, :status, :job_id).to_h, target: target)
    back
  end

  def keep
    result = @draft.keep!(params[:item].to_i)
    result[:path] ? redirect_to(result[:path], notice: result[:notice]) : back(notice: result[:notice])
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    back alert: e.message
  end

  def destroy
    @draft.destroy!
    back
  end

  private

  def set_owner
    if params[:campaign_id]
      @owner = Campaign.find(params[:campaign_id])
      head :forbidden unless table_gm?(@owner)
    else
      @owner = World.find_by!(slug: params[:world_slug])
      head :forbidden unless can_edit_world?(@owner)
    end
  end

  def set_draft
    @draft = Draft.where(owner: @owner).find(params[:id])
  end

  # What the draft is for, from a Global ID, only ever something of this
  # campaign's or world's.
  def find_target(kind)
    return nil if params[:target].blank?

    record = GlobalID::Locator.locate(params[:target]) or raise ActiveRecord::RecordNotFound
    owned = case record
    when Location then @owner.is_a?(Campaign) && record.campaign_id == @owner.id && kind == "mode"
    else @owner.is_a?(World) && record.respond_to?(:world_id) && record.world_id == @owner.id && kind == "description"
    end
    owned ? record : raise(ActiveRecord::RecordNotFound)
  end

  def back(notice: nil, alert: nil)
    fallback = @owner.is_a?(Campaign) ? campaign_path(@owner) : world_path(@owner)
    redirect_back_or_to fallback, notice: notice, alert: alert, status: :see_other
  end
end
