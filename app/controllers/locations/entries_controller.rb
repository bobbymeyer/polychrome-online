# frozen_string_literal: true

# The party goes into a dungeon, at its entrance.
class Locations::EntriesController < ApplicationController
  include LocationScoped

  before_action :require_gm

  def create
    @location.enter!
    back "The party enters #{@location.name}."
  end
end
