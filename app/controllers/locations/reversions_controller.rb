# frozen_string_literal: true

# Undoing one GM change, from the campaign's changes page or here.
class Locations::ReversionsController < ApplicationController
  include LocationScoped

  before_action :require_gm

  def create
    @location.revert!(params.expect(:kind), params[:key].presence)
    back_to = url_from(params[:return_to])
    back_to ? redirect_to(back_to, notice: "Reverted.", status: :see_other) : back("Reverted.")
  end
end
