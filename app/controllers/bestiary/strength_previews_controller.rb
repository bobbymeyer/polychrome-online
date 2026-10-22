# frozen_string_literal: true

module Bestiary
  # The monster form's entry tried as it stands (Monster::Trial on an unsaved Monster) and set among the entries
  # nearest its level, redrawn as the stat block changes. Nothing is validated for saving or kept.
  class StrengthPreviewsController < ApplicationController
    include WorldScoped

    NEIGHBOURS = 6

    before_action :require_world_editor

    def create
      @monster = @world.monsters.new(params.expect(monster: [ :name, :level, :base_type, :second_type, :boss, :undead, :giant,
        { stats: Stats::NAMES, affinities: @world.type_chart.slugs, status_immune: [],
          ai_script: [ MonstersController::AI_RULE_FIELDS ], phases: [ MonstersController::PHASE_FIELDS ] } ]))
      @monster.slug = "preview"
      @monster.name = "This entry" if @monster.name.blank?
      return unless @monster.valid?

      @trial = Monster::Trial.new(@monster, seed: 1)
      near = @world.monsters.where.not(slug: params[:editing].to_s).sort_by { |other| [ (other.level - @monster.level).abs, other.name ] }.first(NEIGHBOURS)
      @neighbours = (near + [ @monster ]).sort_by { |other| [ other.level, other.stats["max_hp"].to_i, other.name ] }
    end
  end
end
