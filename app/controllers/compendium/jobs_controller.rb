# frozen_string_literal: true

module Compendium
  class JobsController < BookEntriesController
    self.entry_class = Job
    self.book_title = "Job Compendium"
    self.book_key = :compendium

    private

    def entry_params
      params.expect(job: [
        :name, :slug, :description, :ability_slots, :desperation, *art_params,
        { stat_multipliers: Stats::NAMES, equip_categories: [], innates: [ %i[stat add percent] ],
          job_levels_attributes: [ %i[id level abp ability_id _destroy] ] }
      ])
    end
  end
end
