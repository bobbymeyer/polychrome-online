# frozen_string_literal: true

# Roll a location for a map place from a Gazetteer template.
class MapNodes::LocationsController < ApplicationController
  include PlaceScoped

  def create
    template = @campaign.world.location_templates.find(params.expect(:location_template_id))
    location = @campaign.locations.create!(location_template: template, overrides: { "name" => @node.name })
    @node.update!(location: location)
    redirect_to location_path(location), status: :see_other
  end
end
