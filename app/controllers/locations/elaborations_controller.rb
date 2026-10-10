# frozen_string_literal: true

# How elaborate a dungeon is (Generators::Elaboration), on the GM's dial:
# extra rooms and passages around the core. Turning it never reshapes the
# core, so it is safe once the story is pinned on.
class Locations::ElaborationsController < ApplicationController
  include LocationScoped

  before_action :require_table_gm

  def update
    @location.elaborate!(params.expect(:level))
    back @location.elaboration.zero? ? "Back to the rolled rooms." : "Elaborated to #{@location.elaboration}."
  end
end
