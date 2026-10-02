# frozen_string_literal: true

module Generation
  module GeneratorTables
    # A story table's coverage (StoryCoverage): where it's thin over a few
    # hundred moments, and a moment to try, for whoever can read the book.
    class CoveragesController < ApplicationController
      before_action :set_table

      def show
        @coverage = StoryCoverage.new(@table)
        @place = params[:place].presence_in(StoryCoverage::PLACES) || "town"
        @period = @coverage.periods.find { |p| p == params[:period] } || @coverage.periods.first
        @extra = params[:facts].to_s
        @ranked, @facts, @problems = @coverage.try(place: @place, period: @period, extra: @extra)
      end

      private

      def set_table
        @world = World.find_by!(slug: params[:world_slug])
        @table = @world.generator_tables.find_by!(slug: params[:generator_table_slug])
        head :not_found unless GeneratorTable::STORY_KINDS.include?(@table.kind)
      end
    end
  end
end
