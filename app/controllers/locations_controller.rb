# frozen_string_literal: true

# A town or dungeon page. Players may look once its map place is revealed;
# renaming it, like every other GM control, is the GM's. The controls are
# resources of their own (app/controllers/locations/): rerolls, pins, stock,
# the boss, rooms, modes, and moving through a dungeon.
class LocationsController < ApplicationController
  include LocationScoped

  before_action :require_gm, except: :show

  def show
    @gm = table_gm?
    head :not_found unless @gm || @location.map_node&.visible?
  end

  def update
    @location.rename!(params.expect(location: [ :name ])[:name])
    back "Renamed."
  end
end
