# frozen_string_literal: true

# Taking the background off a generated image (docs/HANDOFF.md §8), with a
# background-removal service of its own (config/cutout.yml): ComfyUI
# renders the picture, then each one is sent here and comes back cut out.
#
# A removal model takes whatever looks like the background, and on flat art
# drawn on white that includes the white inside the subject: a belly, a
# face, a sail. So the result is mended (#keep_interior): only what's clear
# and connected to the edge of the picture is background; a clear patch
# enclosed by the subject is put back from the picture as rendered. The
# cost: a gap that really is background but is closed in (an arm on a hip)
# is filled too.
module Cutout
  class Error < StandardError; end
  # The service couldn't be reached at all: worth trying again later (Remote).
  class Unreachable < Error; include Remote::Unreachable; end

  # Alpha under this counts as removed.
  CLEAR = 128

  # config/cutout.yml, with the Settings page's address and model taking
  # precedence (SiteSetting).
  def self.config
    overrides = SiteSetting.current.cutout_overrides
    overrides.empty? ? Rails.configuration.x.cutout : Rails.configuration.x.cutout.merge(overrides)
  end

  def self.enabled? = config[:url].present?

  def self.client = Client.new

  # What the pages call it: the model, or the service.
  def self.label = config[:model].presence || "the background remover"

  # The picture with its background taken off and its inside mended.
  # Raises Cutout::Error (or Unreachable) when the service can't do it.
  def self.remove(bytes, client: self.client)
    keep_interior(client.remove(bytes), bytes)
  end

  # Does a PNG have an alpha channel? (colour types 4 and 6, or a tRNS chunk)
  def self.png_alpha?(bytes)
    bytes = bytes.to_s.b
    return false unless bytes.start_with?("\x89PNG".b) && bytes.bytesize > 26

    [ 4, 6 ].include?(bytes.getbyte(25)) || bytes.include?("tRNS".b)
  end

  # The cut-out with the holes inside the subject made opaque again, in the
  # colours of the picture as rendered when it's given. PNG bytes in and out.
  def self.keep_interior(removed, plain = nil)
    require "vips" # libvips: in the image (Dockerfile), loaded only when mending
    cut = Vips::Image.new_from_buffer(removed, "")
    return removed unless cut.has_alpha?

    alpha = cut.extract_band(cut.bands - 1)
    width, height = cut.width, cut.height
    clear = (alpha < CLEAR).ifthenelse(255, 0).cast(:uchar)
    # A clear ring round the picture, so one flood from a corner reaches
    # every clear area that touches an edge: the background.
    ring = clear.embed(1, 1, width + 2, height + 2, extend: :background, background: [ 255 ])
    outside = ring.mutate { |image| image.draw_flood!(128, 0, 0, equal: true) }.crop(1, 1, width, height)
    holes = (outside == 255)
    return removed if holes.max.zero?

    # Take in the soft edge round each hole too.
    holes = holes.morph(Vips::Image.new_from_array(Array.new(5) { Array.new(5, 255) }), :dilate)
    colours = plain_colours(plain, cut) || cut.extract_band(0, n: cut.bands - 1)
    colours.bandjoin(holes.ifthenelse(255, alpha).cast(:uchar)).pngsave_buffer
  end

  def self.plain_colours(plain, cut)
    return unless plain

    image = Vips::Image.new_from_buffer(plain, "")
    return unless image.width == cut.width && image.height == cut.height

    image = image.extract_band(0, n: image.bands - 1) if image.has_alpha?
    image.bands == cut.bands - 1 ? image.cast(cut.format) : nil
  end
  private_class_method :plain_colours
end
