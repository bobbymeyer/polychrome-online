# frozen_string_literal: true

# The GM settling a choice on one option (Message#settle!).
class Choices::SettlementsController < ApplicationController
  include ChoiceScoped

  before_action :require_table_gm

  def create
    @choice.settle!(params[:option])
    redirect_back_or_to campaign_table_path(@campaign), status: :see_other
  rescue Refusal => e
    forbid(e.message)
  end
end
