# frozen_string_literal: true

# A town's services, paid from the party's purse (Campaign#use_service!):
# a room at the inn, a raising at the temple, a rumour at the guild. A
# player pays for their own character; the GM for anyone.
class Locations::ServicesController < ApplicationController
  include LocationScoped

  before_action :require_party_in_town

  def create
    if params[:everyone].present?
      @campaign.rest_at_inn!(at: @location, by: payer_name)
      back "Everyone takes a room for the night."
    else
      character = @campaign.characters.find(params.expect(:character_id))
      return forbid("#{character.name} isn't yours to pay for.") unless can_manage?(character)

      back @campaign.use_service!(params.expect(:kind), character, at: @location, by: payer_name)
    end
  end

  private

  def away_message = "Services are for the town where the party is."

  def back_anchor = "service-#{params[:kind] || 'inn'}"
end
