# frozen_string_literal: true

module Encounters
  class EncounterTablesController < BookEntriesController
    self.entry_class = EncounterTable
    self.book_title = "Encounter Tables"
    self.book_key = :encounters

    private

    def ordered(relation)
      relation.order(:tier, :terrain, :name)
    end

    def entry_params
      params.expect(encounter_table: [
        :name, :slug, :terrain, :tier, :description, *art_params,
        { entries: [ %i[weight monster count monster_2 count_2] ] }
      ])
    end
  end
end
