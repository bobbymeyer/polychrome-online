# frozen_string_literal: true

class Characters::AbilitySlotsController < ApplicationController
  include CampaignScoped

  before_action :set_character
  before_action :require_character_manager

  def update
    ids = params.fetch(:ability_slots, {}).permit(abilities: []).fetch(:abilities, []).compact_blank
    abilities = @world.abilities.where(id: ids).index_by(&:id)
    @character.set_ability_slots!(ids.map { |id| abilities[id.to_i] })
    redirect_to character_path(@character), notice: "Abilities set.", status: :see_other
  end
end
