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
      params.expect(ability: [ :name, :slug, :kind, :target, :mp_cost, :gesture, :description, *art_params,
                              { effects: [ effect_fields ] } ])
    end
  end
end
