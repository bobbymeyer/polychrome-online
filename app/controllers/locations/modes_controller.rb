# frozen_string_literal: true

# A place's other states, prepared by the GM (Location::Modes).
class Locations::ModesController < ApplicationController
  include LocationScoped

  before_action :require_gm

  def create
    fields = params.expect(mode: [ :name, :line, :description, :music, :encounters, :art, :activities, { closed: [], times: [] } ])
    @location.add_mode!(fields.to_h)
    back "#{fields[:name]} is ready to set off."
  rescue ActiveRecord::RecordInvalid => e
    back alert: e.record.errors.full_messages.to_sentence
  end

  def destroy
    @location.remove_mode!(params.expect(:id))
    back "Mode removed."
  end
end
