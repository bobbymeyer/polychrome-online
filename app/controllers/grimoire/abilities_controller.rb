# frozen_string_literal: true

module Grimoire
  class AbilitiesController < BookEntriesController
    self.entry_class = Ability
    self.book_title = "Grimoire"
    self.book_key = :grimoire

    private

    def ordered(relation)
      relation.order(:kind, :name)
    end

    def entry_params
      params.expect(ability: [ :name, :slug, :kind, :target, :mp_cost, :hp_cost, :charge, :interrupt, :reload_turns, :reach, :again, :gesture,
                                :field_skill, :field_outcome, :field_difficulty, :field_power, :description, *art_params,
                              { effects: [ effect_fields ] } ])
    end
  end
end
