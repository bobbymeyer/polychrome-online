# frozen_string_literal: true

# Finds what the asset pipeline (§8) is working on, from request params,
# within the world in the URL: a book entry (entry_type + entry_slug), or a
# speaker (owner_type + owner_id) and one of their portraits.
module ArtTargets
  extend ActiveSupport::Concern

  BOOK_CLASSES = { "monster" => Monster, "job" => Job, "item" => Item, "ability" => Ability, "location_template" => LocationTemplate,
                   "encounter_table" => EncounterTable }.freeze
  SPEAKER_CLASSES = { "npc" => Npc, "character" => Character }.freeze

  private

  def set_world
    @world = World.find_by!(slug: params[:world_slug])
  end

  def art_entry
    book = BOOK_CLASSES.fetch(params[:entry_type].to_s) { raise ActiveRecord::RecordNotFound }
    book.find_by!(world: @world, slug: params[:entry_slug])
  end

  def art_speaker
    speakers = SPEAKER_CLASSES.fetch(params[:owner_type].to_s) { raise ActiveRecord::RecordNotFound }
    speakers.joins(:campaign).where(campaigns: { world_id: @world.id }).find(params[:owner_id])
  end

  def speaker_request?
    params[:entry_type] == "portrait"
  end
end
