# frozen_string_literal: true

module Gazetteer
  module LocationTemplates
    # A hundred rolls of a template, counted (Generators::Report): what it
    # tends to make, which rows never come up, and where it falls back on
    # placeholders. Read-only, like the template's page.
    class ReportsController < ApplicationController
      SEEDS = 1..100

      def show
        @world = World.find_by!(slug: params[:world_slug])
        @template = @world.location_templates.find_by!(slug: params[:location_template_slug])
        settings = @template.settings
        tables = @template.table_entries
        @report = if @template.town?
                    Generators::Report.town(template: settings, tables: tables, seeds: SEEDS)
        else
                    Generators::Report.dungeon(template: settings, tables: tables, encounters: @template.encounter_table&.entries || [], seeds: SEEDS,
                                               lore: @world.lore, family_names: @world.family_names)
        end
      end
    end
  end
end
