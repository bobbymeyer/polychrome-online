class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :entry_page

  private

  # A book entry's page, from the entry alone (the asset pipeline, §8).
  def entry_page(entry, **options)
    polymorphic_path([ entry.world, ArtDirection::BOOKS.fetch(entry.art_kind), entry ], **options)
  end
end
