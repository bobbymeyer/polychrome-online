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
      params.expect(generator_table: [ :name, :slug, :kind, :description, :paste,
                                       { entries: [ %i[text key weight service item gil width height roof makes rooms heart keeps named did sealed trace dead town] ] } ])
    end
  end
end
