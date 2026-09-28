# frozen_string_literal: true

module Grimoire
  # Writes a tiered family of abilities (AbilityFamily) into the Grimoire.
  class FamiliesController < ApplicationController
    before_action :set_world
    before_action :require_world_editor

    # Suggested names (Drafts::Family) arrive filled in.
    def new
      @family = AbilityFamily.new(world: @world, shape: "caster", type: @world.type_chart.slugs.second || @world.type_chart.plain)
      @family.assign_attributes(family_params) if params[:family]
    end

    def create
      @family = AbilityFamily.new(family_params.merge(world: @world))
      if (written = @family.save)
        redirect_to world_grimoire_abilities_path(@world),
                    notice: "Wrote #{written.map(&:name).to_sentence}#{" into the #{@family.job.name}'s learn table" if @family.job}."
      else
        render :new, status: :unprocessable_content
      end
    end

    private

    def set_world
      @world = World.find_by!(slug: params[:world_slug])
    end

    def family_params
      fields = params.expect(family: [ :root, :shape, :type, :status, :job_id, { tiers: [ %i[name description power mp level] ] } ])
      # Tiers by position: "0".."3", any of them left out.
      posted = fields[:tiers].respond_to?(:each_pair) ? fields[:tiers].to_h : {}
      fields[:tiers] = Array.new(4) { |i| posted[i.to_s] || {} }
      fields
    end
  end
end
