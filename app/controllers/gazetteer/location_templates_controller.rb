# frozen_string_literal: true

module Gazetteer
  class LocationTemplatesController < BookEntriesController
    self.entry_class = LocationTemplate
    self.book_title = "Gazetteer"
    self.book_key = :gazetteer

    private

    def ordered(relation)
      relation.order(:kind, :name)
    end

    def entry_params
      params.expect(location_template: [
        :name, :slug, :kind, :encounter_table_id, :description, *art_params,
        { config: [ :loops, :npcs_min, :npcs_max, :stock_min, :stock_max, :buildings_min, :buildings_max, :rooms_min, :rooms_max,
                    :boss_monster, :boss_count, { services: Generators::Town::SERVICES, decisions: %w[encounter event treasure fork], tables: [] } ] }
      ])
    end
  end
end
