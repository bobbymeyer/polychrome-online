# frozen_string_literal: true

module Bestiary
  class MonstersController < BookEntriesController
    self.entry_class = Monster
    self.book_title = "Bestiary"
    self.book_key = :bestiary

    # The form's rows, as the form and its live reading of them (BehaviorPreviewsController) both take them.
    AI_RULE_FIELDS = [ :use, :target, :once, :say, :when, :by, *Battle::AI::CONDITIONS ].freeze
    PHASE_FIELDS = %i[hp_below becomes say restore].freeze

    # ?from=slug starts the form from another entry (not its picture, and not its name: a slug can't be shared).
    def new
      super
      source = scope.find_by(slug: params[:from]) if params[:from].present?
      return unless source

      @entry = source.dup.tap { |copy| copy.slug = nil; copy.name = "#{source.name} (copy)" }
    end

    private

    def ordered(relation)
      relation.order(:level, :name)
    end

    def entry_params
      params.expect(monster: [
        :name, :slug, :level, :description, :base_type, :second_type, :exp, :gil, :abp, :boss, :undead, :giant, :boss_line, :music, *art_params,
        { stats: Stats::NAMES, affinities: @world.type_chart.slugs, status_immune: [],
          ai_script: [ AI_RULE_FIELDS ], drops: [ %i[item chance] ],
          phases: [ PHASE_FIELDS ] }
      ])
    end
  end
end
