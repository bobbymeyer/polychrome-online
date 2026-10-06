# frozen_string_literal: true

# Loads a choice put to the table (a Message of kind "choice").
module ChoiceScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_choice
  end

  private

  def set_choice
    @choice = Message.where(kind: "choice").find(params[:choice_id])
    @campaign = @choice.campaign
    @world = @campaign.world
  end
end
