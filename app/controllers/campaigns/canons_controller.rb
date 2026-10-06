# frozen_string_literal: true

# Bringing a setting's canon into a campaign (Atlas): the places and people
# the world has that the campaign doesn't yet.
class Campaigns::CanonsController < Campaigns::BaseController
  before_action :require_campaign_gm

  def create
    places, figures = Atlas.new(@campaign).bring_in_all!
    notice = [ ("#{helpers.pluralize(places.size, 'place')} on the map" if places.any?), ("#{helpers.pluralize(figures.size, 'person', plural: 'people')} in the cast" if figures.any?) ].compact
    redirect_to campaign_path(@campaign), notice: notice.any? ? "From #{@world.name}: #{notice.to_sentence}." : "Nothing new from #{@world.name}.", status: :see_other
  end
end
