# frozen_string_literal: true

# How a fight the GM is setting up is likely to go (Battle::Forecast): the
# battle form and the scene form ask as their fields change.
class Campaigns::ForecastsController < ApplicationController
  include CampaignScoped

  RUNS = 20

  before_action :set_campaign
  before_action :require_campaign_gm

  def show
    scope = params.key?(:scene) ? :scene : :battle
    raw = params.fetch(scope, ActionController::Parameters.new).permit(characters: [], encounter: [ %i[monster count] ])
    encounter = JsonCasting.rows(raw[:encounter]).each_with_object(Hash.new(0)) do |row, counts|
      counts[row["monster"]] += row["count"].to_i.clamp(1, 9) if row["monster"].present?
    end
    ids = Array(raw[:characters]).compact_blank
    characters = ids.any? ? @campaign.characters.where(id: ids) : @campaign.characters.select(&:conscious?)
    known = @world.monsters.where(slug: encounter.keys).pluck(:slug)
    encounter = encounter.slice(*known)

    @forecast = if characters.any? && encounter.any?
      party = characters.map(&:battle_spec)
      Battle::Forecast.run((1..RUNS).map { |seed| @world.battle(seed: seed, party: party, monsters: encounter) })
    end
    render partial: "campaigns/forecasts/forecast", locals: { forecast: @forecast }
  end
end
