# frozen_string_literal: true

# A new seed for a town or dungeon (Location#reroll!): pinned things stay.
class Locations::RerollsController < ApplicationController
  include LocationScoped

  before_action :require_gm

  def create
    @location.reroll!
    back "Rerolled. Pinned things stayed put."
  end
end
