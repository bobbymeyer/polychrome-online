# frozen_string_literal: true

# Where the party is in a dungeon: moving plays the room's decision.
class Locations::PositionsController < ApplicationController
  include LocationScoped

  before_action :require_gm

  def update
    @location.move_to!(params.expect(:room))
    back
  end
end
