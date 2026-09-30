# frozen_string_literal: true

# Asking the language model for suggestions (Draft), or throwing them away
# (keeping one is Drafts::KeepsController). Prep drafts belong to a campaign
# and are the GM's; world-building drafts belong to a world and are its
# editors'.
class DraftsController < ApplicationController
  include DraftOwned

  def create
    kind = params.expect(:kind)
    return back(alert: "Pick something to suggest") unless Draft::KINDS.include?(kind)
    return back(alert: "No language model is set up (LLM_URL)") unless Llm.enabled?

    target = find_target(kind)
    Draft.start!(@owner, kind, params.fetch(:draft, {}).permit(:idea, :pitch, :root, :shape, :type, :status, :job_id).to_h, target: target)
    back
  end

  def destroy
    Draft.where(owner: @owner).find(params[:id]).destroy!
    back
  end

  private

  # What the draft is for, from a Global ID, only ever something of this
  # campaign's or world's.
  def find_target(kind)
    return nil if params[:target].blank?

    record = GlobalID::Locator.locate(params[:target]) or raise ActiveRecord::RecordNotFound
    owned = case record
    when MapNode then @owner.is_a?(Campaign) && record.campaign_id == @owner.id && kind == "mode"
    else @owner.is_a?(World) && record.respond_to?(:world_id) && record.world_id == @owner.id && kind == "description"
    end
    owned ? record : raise(ActiveRecord::RecordNotFound)
  end
end
