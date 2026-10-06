# frozen_string_literal: true

module Generation
  # Every fact a story row can ask about (Campaign::Moment::FACTS), for
  # whoever writes rows: read-only, beside the Generator Tables.
  class FactsController < ApplicationController
    include WorldScoped

    def show
      @tables = @world.generator_tables.where(kind: GeneratorTable::STORY_KINDS).order(:name)
    end
  end
end
