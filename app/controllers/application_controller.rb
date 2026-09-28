class ApplicationController < ActionController::Base
  include Authentication
  include Authorization
  include LocalCoop
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :entry_page

  private

  # Where something with generated art is edited, from the thing alone (the
  # asset pipeline, §8): a book entry's page, a speaker's edit page, or the
  # location a mode's picture belongs to.
  def entry_page(entry, **options)
    case entry
    when Portrait then polymorphic_path([ :edit, entry.owner ], **options)
    when ModeArt then location_path(entry.location, **options)
    else polymorphic_path([ entry.world, ArtDirection::BOOKS.fetch(entry.art_kind), entry ], **options)
    end
  end
end
