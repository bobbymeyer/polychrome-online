# frozen_string_literal: true

module Bestiary
  # A creature tried against a party (Monster::Trial; level 5 or its own, or the ?level= asked for): read-only,
  # for whoever can read the Bestiary.
  class TrialsController < ApplicationController
    include WorldScoped

    def show
      @monster = @world.monsters.find_by!(slug: params[:monster_slug])
      count = params[:count].present? ? params[:count].to_i.clamp(1, 8) : nil # none given: one boss, or two of anything else
      level = params[:level].presence&.to_i
      @trial = Monster::Trial.new(@monster, count: count, seed: params.fetch(:seed, @monster.id).to_i, level: level)
    end
  end
end
