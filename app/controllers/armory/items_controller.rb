# frozen_string_literal: true

module Armory
  class ItemsController < BookEntriesController
    self.entry_class = Item
    self.book_title = "Armory"
    self.book_key = :armory

    private

    def ordered(relation)
      relation.order(:category, :name)
    end

    def entry_params
      params.expect(item: [ :name, :slug, :category, :price, :target, :description, *art_params,
                           { stats: Stats::NAMES, effects: [ effect_fields ] } ])
    end
  end
end
