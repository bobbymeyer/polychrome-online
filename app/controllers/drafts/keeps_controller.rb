# frozen_string_literal: true

# Keeping one of a draft's suggestions (Draft#keep!): it becomes a secret,
# a clock, a skill, or fills in a form, whatever the draft was for.
class Drafts::KeepsController < ApplicationController
  include DraftOwned

  def create
    draft = Draft.where(owner: @owner).find(params[:draft_id])
    result = draft.keep!(params[:item].to_i)
    result[:path] ? redirect_to(result[:path], notice: result[:notice]) : back(notice: result[:notice])
  rescue Refusal, ActiveRecord::RecordInvalid => e
    back alert: e.message
  end
end
