# frozen_string_literal: true

# An upload of a package (PackageArchive), refused by its size before it's
# read. Rails writes a request's whole body to disk the first time params are
# read, and a world's own filter reads them, so this goes before every other.
#   package_upload "polychrome-module", only: :create
module PackageUpload
  extend ActiveSupport::Concern

  # Room for the rest of the form around the file.
  FORM_BYTES = 1.megabyte

  class_methods do
    def package_upload(format, **options)
      kind = PackageArchive::KINDS.fetch(format)
      prepend_before_action(**options) do
        too_big = request.content_length.to_i > kind[:max_bytes] + FORM_BYTES
        raise Refusal, "That file is too big to be #{kind[:what]} (#{kind[:max_bytes] / 1.megabyte} MB at most)." if too_big
      end
    end
  end
end
