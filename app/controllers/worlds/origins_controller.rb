# frozen_string_literal: true

# Where characters in a setting can come from (World#origins): each a name,
# a line, and optionally a skill they're better at.
class Worlds::OriginsController < ApplicationController
  before_action :set_world
  before_action :require_world_editor, except: :show

  def show; end

  def edit; end

  def update
    if @world.update(origins: posted_rows)
      redirect_to world_origins_path(@world), notice: "Origins saved."
    else
      flash.now[:alert] = @world.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_world
    @world = World.find_by!(slug: params[:world_slug])
  end

  # Kept and added origins, in the form's order. A new one's id comes from its name.
  def posted_rows
    rows = JsonCasting.rows(params.permit(origins: %i[slug name skill description remove]).fetch(:origins, {}))
    rows.filter_map do |row|
      row = row.to_h.with_indifferent_access
      next if row[:remove] == "1"

      slug = row[:slug].presence || row[:name].to_s.parameterize(separator: "_")
      next if slug.blank?

      { "slug" => slug, "name" => row[:name].to_s.strip, "skill" => row[:skill].presence, "description" => row[:description].to_s.strip }.compact
    end
  end
end
