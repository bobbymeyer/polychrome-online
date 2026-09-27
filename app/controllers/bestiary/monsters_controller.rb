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
        :name, :slug, :level, :description, :exp, :gil, :abp, :boss, :boss_line, *art_params,
        { stats: Stats::NAMES, elements: Battle::ELEMENTS, status_immune: [],
          ai_script: [ [ :use, :target, *Battle::AI::CONDITIONS ] ], drops: [ %i[item chance] ] }
      ])
    end
  end
end
