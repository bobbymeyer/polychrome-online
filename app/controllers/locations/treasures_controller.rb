# frozen_string_literal: true

# A room's treasure, handed to the party.
class Locations::TreasuresController < ApplicationController
  include LocationScoped

  before_action :require_gm

  def create
    @location.take_treasure!(params.expect(:room))
    back "Added to the party bag."
  end
end
