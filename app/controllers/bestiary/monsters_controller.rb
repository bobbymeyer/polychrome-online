# frozen_string_literal: true

module Bestiary
  class MonstersController < BookEntriesController
    self.entry_class = Monster
    self.book_title = "Bestiary"
    self.book_key = :bestiary

    private

    def ordered(relation)
      relation.order(:level, :name)
    end

    def entry_params
      params.expect(monster: [
        :name, :slug, :level, :description, :base_type, :exp, :gil, :abp, :boss, :undead, :boss_line, *art_params,
        { stats: Stats::NAMES, affinities: @world.type_chart.slugs, status_immune: [],
          ai_script: [ [ :use, :target, :once, :say, *Battle::AI::CONDITIONS ] ], drops: [ %i[item chance] ],
          phases: [ %i[hp_below becomes say restore] ] }
      ])
    end
  end
end
