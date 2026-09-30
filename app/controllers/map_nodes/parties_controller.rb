# frozen_string_literal: true

# The GM putting the party somewhere on the map directly (Campaign#place_party!).
class MapNodes::PartiesController < ApplicationController
  include PlaceScoped
  include MapGm

  def create
    @campaign.place_party!(@node)
    panel notice: "The party is at #{@node.name}."
  end
end
