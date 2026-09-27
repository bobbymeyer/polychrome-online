# frozen_string_literal: true

# A world's art direction (docs/HANDOFF.md §8): the house style every prompt
# starts from, and the framing for each content type. Both layers can name a
# model and stack LoRAs. The entry's own layer is edited on its page.
class ArtDirectionsController < ApplicationController
  before_action :require_admin
  before_action :set_world

  def show
    @types = ArtDirection::KINDS.map { |kind| @world.art_type(kind) }
  end


  def update
    ArtType.transaction do
      @world.update!(params.expect(world: [ :art_style, :art_negative, :art_model, { art_loras: {} } ]))
      params.fetch(:types, {}).each do |kind, attrs|
        next unless ArtDirection::KINDS.include?(kind)

        @world.art_type(kind).update!(attrs.permit(:prompt, :negative, :model, :width, :height, :transparent, loras: {}))
      end
    end
    redirect_to world_art_direction_path(@world), notice: "Art direction saved."
  rescue ActiveRecord::RecordInvalid => e
    @types = ArtDirection::KINDS.map { |kind| @world.art_type(kind) }
    flash.now[:alert] = e.record.errors.full_messages.to_sentence
    render :show, status: :unprocessable_content
  end

  private

  def set_world
    @world = World.find_by!(slug: params[:world_slug])
  end
end
