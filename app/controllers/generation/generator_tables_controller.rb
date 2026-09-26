# frozen_string_literal: true

module Generation
  class GeneratorTablesController < BookEntriesController
    self.entry_class = GeneratorTable
    self.book_title = "Generator Tables"
    self.book_key = :generation

    private

    def ordered(relation)
      relation.order(:kind, :name)
    end

    def entry_params
      params.expect(generator_table: [ :name, :slug, :kind, :description, *art_params,
                                       { entries: [ %i[text weight service item width height roof] ] } ])
    end
  end
end
