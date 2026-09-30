# frozen_string_literal: true

# Someone the GM writes into a town.
class Locations::NpcsController < ApplicationController
  include LocationScoped

  before_action :require_table_gm

  def create
    fields = params.expect(npc: %i[name title description])
    @campaign.npcs.create!(fields.merge(location: @location))
    @location.touch
    back "#{fields[:name]} added to #{@location.name}."
  rescue ActiveRecord::RecordInvalid => e
    back alert: e.record.errors.full_messages.to_sentence
  end
end
