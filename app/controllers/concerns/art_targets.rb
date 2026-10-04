# frozen_string_literal: true

# Finds what the asset pipeline (§8) is working on, from request params,
# within the world in the URL: a book entry (entry_type + entry_slug), a
# speaker (owner_type + owner_id) and one of their portraits, or a location
# (location_id + mode) and one of its modes' pictures.
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

  def sprite_request?
    params[:entry_type] == "sprite"
  end

  def mode_request?
    params[:entry_type] == "mode"
  end

  def beat_request?
    params[:entry_type] == "beat"
  end

  def map_request?
    params[:entry_type] == "map"
  end

  # A map's picture: a setting's (map_type "world") or a campaign's.
  def art_map
    if params[:map_type] == "world"
      @world.world_maps.find(params[:map_id])
    else
      Map.joins(:campaign).where(campaigns: { world_id: @world.id }).find(params[:map_id])
    end
  end

  # A scene's beat, whose panel is being made.
  def art_beat
    Beat.joins(scene: :campaign).where(campaigns: { world_id: @world.id }).find(params[:beat_id])
  end

  # The picture for one of a location's modes, made when first asked for.
  def art_mode
    location = Location.joins(:campaign).where(campaigns: { world_id: @world.id }).find(params[:location_id])
    mode = location.map_node.modes.find_by!(key: params[:mode].to_s)
    location.mode_arts.find_or_create_by!(mode: mode)
  end
end
