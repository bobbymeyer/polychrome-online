# frozen_string_literal: true

module Generation
  # Every fact a story row can ask about (Campaign::Moment::FACTS), for
  # whoever writes rows: read-only, beside the Generator Tables.
  class FactsController < ApplicationController
    before_action :set_world

    def show
      @tables = @world.generator_tables.where(kind: GeneratorTable::STORY_KINDS).order(:name)
    end

    private

    def set_world
      @world = World.find_by!(slug: params[:world_slug])
    end
  end
end
