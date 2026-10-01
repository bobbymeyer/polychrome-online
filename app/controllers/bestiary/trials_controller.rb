# frozen_string_literal: true

module Bestiary
  # A creature tried against a level-5 party (Monster::Trial): read-only,
  # for whoever can read the Bestiary.
  class TrialsController < ApplicationController
    before_action :set_world

    def show
      @monster = @world.monsters.find_by!(slug: params[:monster_slug])
      @trial = Monster::Trial.new(@monster, count: params.fetch(:count, 2).to_i.clamp(1, 8), seed: params.fetch(:seed, @monster.id).to_i)
    end

    private

    def set_world
      @world = World.find_by!(slug: params[:world_slug])
    end
  end
end
