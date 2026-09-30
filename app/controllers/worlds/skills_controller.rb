# frozen_string_literal: true

# A world's skills (World#skills): what its checks are made with, each on a
# stat. A removed skill comes off the jobs that were good at it.
class Worlds::SkillsController < ApplicationController
  before_action :set_world
  before_action :require_world_editor, only: %i[edit update]

  def show; end

  def edit; end

  def update
    rows = posted_rows
    removed = Array(@world.skills).map { |s| s["slug"] } - rows.map { |s| s["slug"] }
    saved = World.transaction do
      @world.update(skills: rows) or raise ActiveRecord::Rollback
      @world.jobs.each { |job| job.update_columns(skills: job.skills - removed) if job.skills.intersect?(removed) }
    end
    if saved
      redirect_to world_skills_path(@world), notice: "Skills saved."
    else
      flash.now[:alert] = @world.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_world
    @world = World.find_by!(slug: params[:world_slug])
  end

  # Kept and added skills, in the form's order. A new skill's id comes
  # from its name.
  def posted_rows
    rows = JsonCasting.rows(params.permit(skills: %i[slug name stat description remove]).fetch(:skills, {}))
    rows.filter_map do |row|
      row = row.to_h.with_indifferent_access
      next if row[:remove] == "1"

      slug = row[:slug].presence || row[:name].to_s.parameterize(separator: "_")
      next if slug.blank?

      { "slug" => slug, "name" => row[:name].to_s.strip, "stat" => row[:stat].to_s, "description" => row[:description].to_s.strip }
    end
  end
end
