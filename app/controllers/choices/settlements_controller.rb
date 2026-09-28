# frozen_string_literal: true

# The GM settling a choice on one option (Message#settle!).
class Choices::SettlementsController < ApplicationController
  include ChoiceScoped

  def create
    return forbid("Only the GM settles a choice.") unless table_seat == "gm"

    @choice.settle!(params[:option])
    head :no_content
  rescue Refusal => e
    forbid(e.message)
  end
end
