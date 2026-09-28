# frozen_string_literal: true

# The mode a place is in: set off at the table, or ended.
class Locations::CurrentModesController < ApplicationController
  include LocationScoped

  before_action :require_gm

  def update
    @location.switch_mode!(params.expect(:key))
    back "#{@location.name}: #{@location.current_mode['name']}."
  end

  def destroy
    @location.clear_mode!(params[:line])
    back "#{@location.name} is itself again."
  end
end
