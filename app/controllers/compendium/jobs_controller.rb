# frozen_string_literal: true

module Compendium
  class JobsController < BookEntriesController
    self.entry_class = Job
    self.book_title = "Archetype Compendium"
    self.book_key = :compendium

    private

    def entry_params
      params.expect(job: [
        :name, :slug, :description, :base_type, :ability_slots, :desperation, :signature, :passive, :field_ability, *art_params,
        { payoff: %i[kind amount line], stat_multipliers: Stats::NAMES, equip_categories: [], skills: [], innates: [ %i[stat add percent] ],
          job_levels_attributes: [ %i[id level ability_id _destroy] ] }
      ])
    end
  end
end
