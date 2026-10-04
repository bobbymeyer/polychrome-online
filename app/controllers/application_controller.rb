class ApplicationController < ActionController::Base
  include Authentication
  include Authorization
  include LocalCoop
  include TableSeat # your seat at a campaign's table, for the account menu on every page in it
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :entry_page

  # The game said no: tell whoever asked, back where they were. Controllers
  # that know a better place to say it rescue it themselves.
  rescue_from Refusal do |refusal|
    respond_to do |format|
      format.html { redirect_back_or_to root_path, alert: refusal.message, status: :see_other }
      format.any { head :unprocessable_content }
    end
  end

  private

  # Where something with generated art is edited, from the thing alone (the
  # asset pipeline, §8): a book entry's page, a speaker's edit page, or the
  # location a mode's picture belongs to.
  def entry_page(entry, **options)
    case entry
    when Portrait, Sprite then polymorphic_path([ :edit, entry.owner ], **options)
    when ModeArt then location_path(entry.location, **options)
    when Beat then edit_scene_path(entry.scene, beat: entry.id, **options)
    when Map then campaign_maps_path(entry.campaign, map: entry.id, **options)
    when WorldMap then world_world_places_path(entry.world, map: entry.id, **options)
    else polymorphic_path([ entry.world, ArtDirection::BOOKS.fetch(entry.art_kind), entry ], **options)
    end
  end
end
