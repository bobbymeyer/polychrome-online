# frozen_string_literal: true

# Taking the background off a generated image (docs/HANDOFF.md §8), with a
# background-removal service of its own (config/cutout.yml): ComfyUI
# renders the picture, then each one is sent here and comes back cut out.
#
# A removal model takes whatever looks like the background, and on art
# drawn on white that includes the white inside the subject: a shirt, a
# face, a sail. Two things keep the white:
#
# - The picture is rendered on a ground of its own colour (#on_ground: a
#   flat green by default, in place of the type's "white background"), so
#   white in the design is never the ground's colour.
# The remover is hardwired: its address is this machine's port 7071 unless
# told otherwise, and the app starts bin/cutout there itself when nothing
# answers (Cutout::Launcher), so there is nothing to set.
#
# - The cut-out is mended (#keep_interior): a cleared pixel counts as
#   background only if its colour is the ground's and it reaches the edge
#   of the picture through ground-coloured pixels. Anything else the model
#   cleared was part of the subject, and is put back from the picture as
#   rendered. On a white ground (no ground set), a white patch closed in
#   by the subject is put back too, since it can't be told apart; the
#   cost is a gap that really is background but closed in (an arm on a
#   hip), filled.
module Cutout
  class Error < StandardError; end
  # The service couldn't be reached at all: worth trying again later (Remote).
  class Unreachable < Error; include Remote::Unreachable; end

  # Alpha under this counts as removed.
  CLEAR = 128
  # A ground this light is white, as far as telling it from a design goes.
  WHITE = 200
  # The type framings' own words for the ground, swapped for ours.
  WHITE_GROUND = /\b(?:(?:plain|flat|simple|solid)\s+)*(?:white|plain|blank)\s+background\b/i

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

  # The colour pictures are rendered on when they'll be cut out, or nil.
  def self.ground = config[:ground].to_s.strip.presence

  def self.tolerance = (config[:tolerance].to_i.positive? ? config[:tolerance].to_i : 56)

  # The ground's words, for a prompt: "plain flat green background, no shadow".
  def self.ground_prompt = ground && "plain flat #{ground} background, no shadow"

  # A recipe's framing on the ground instead of white (ArtBatch.start!):
  # the type's white background is swapped for the ground, or the ground
  # added, and the prompt put back together; a white background is asked
  # against, where the model takes a negative prompt.
  def self.on_ground(recipe)
    phrase = ground_prompt or return recipe
    parts = recipe.fetch("parts", {}).dup
    framing = parts["framing"].to_s
    parts["framing"] = framing.match?(WHITE_GROUND) ? framing.sub(WHITE_GROUND, phrase) : ArtDirection.join_prompt(framing, phrase)
    recipe = recipe.merge("parts" => parts, "positive" => ArtDirection.compose(parts), "ground" => ground)
    recipe["negative"] = ArtDirection.join_prompt(recipe["negative"], "white background") if recipe["negative"].present?
    recipe
  end

  # The picture with its background taken off and its inside mended.
  # Raises Cutout::Error (or Unreachable) when the service can't do it.
  # A remover on this machine that isn't running yet is started first
  # (Launcher).
  def self.remove(bytes, client: self.client)
    Launcher.ensure_running!
    keep_interior(client.remove(bytes), bytes)
  end

  # Does a PNG have an alpha channel? (colour types 4 and 6, or a tRNS chunk)
  def self.png_alpha?(bytes)
    bytes = bytes.to_s.b
    return false unless bytes.start_with?("\x89PNG".b) && bytes.bytesize > 26

    [ 4, 6 ].include?(bytes.getbyte(25)) || bytes.include?("tRNS".b)
  end

  # The cut-out with what was taken out of the subject made opaque again,
  # in the colours of the picture as rendered when it's given (under the
  # cleared pixels too, so dropping the alpha gives the render back: see
  # #opaque). PNG bytes in and out. tolerance: how far from the ground's
  # colour still counts as ground.
  def self.keep_interior(removed, plain = nil, tolerance: self.tolerance)
    require "vips" # libvips: in the image (Dockerfile), loaded only when mending
    cut = Vips::Image.new_from_buffer(removed, "")
    return removed unless cut.has_alpha?

    alpha = cut.extract_band(cut.bands - 1)
    width, height = cut.width, cut.height
    rendered = plain_colours(plain, cut)
    colours = rendered || cut.extract_band(0, n: cut.bands - 1)
    ground = ground_colour(colours)
    clear = alpha < CLEAR
    groundish = near(colours, ground, tolerance)

    # The background: ground-coloured, cleared, and reaching the edge. A
    # clear ring round the picture, so one flood from a corner reaches
    # every such area that touches an edge.
    candidates = (clear & groundish).ifthenelse(255, 0).cast(:uchar)
    ring = candidates.embed(1, 1, width + 2, height + 2, extend: :background, background: [ 255 ])
    outside = ring.mutate { |image| image.draw_flood!(128, 0, 0, equal: true) }.crop(1, 1, width, height) == 128

    # What comes back: cleared but not ground-coloured (taken out of the
    # subject); and, on a white ground, cleared ground-coloured patches
    # closed in by the subject (white inside, most likely).
    restore = ground.all? { |c| c >= WHITE } ? (clear & (outside == 0)) : (clear & (groundish == 0))
    # Specks and pinholes aside (a 3×3 open, then close).
    kernel = Vips::Image.new_from_array(Array.new(3) { Array.new(3, 255) })
    restore = restore.ifthenelse(255, 0).cast(:uchar).morph(kernel, :erode).morph(kernel, :dilate).morph(kernel, :dilate).morph(kernel, :erode)
    return removed if restore.max.zero? && rendered.nil?

    colours.bandjoin(restore.ifthenelse(255, alpha).cast(:uchar)).pngsave_buffer
  end

  # The picture without its alpha: a cut-out back as it was rendered, on its
  # ground, for redrawing from (a draft made properly). PNG bytes in and out.
  def self.opaque(bytes)
    require "vips"
    image = Vips::Image.new_from_buffer(bytes, "")
    image.has_alpha? ? image.extract_band(0, n: image.bands - 1).pngsave_buffer : bytes
  end

  # The ground's colour: the picture's border, averaged.
  def self.ground_colour(colours)
    width, height = colours.width, colours.height
    strips = [ colours.crop(0, 0, width, 1), colours.crop(0, height - 1, width, 1), colours.crop(0, 0, 1, height), colours.crop(width - 1, 0, 1, height) ]
    (0...colours.bands).map { |band| strips.sum { |strip| strip.extract_band(band).avg } / strips.size }
  end

  # Where the picture is within `tolerance` of a colour, per channel (as RMS).
  def self.near(colours, colour, tolerance)
    diff = colours.cast(:float) - colour
    (diff * diff).bandmean < tolerance**2
  end
  private_class_method :near

  def self.plain_colours(plain, cut)
    return unless plain

    image = Vips::Image.new_from_buffer(plain, "")
    return unless image.width == cut.width && image.height == cut.height

    image = image.extract_band(0, n: image.bands - 1) if image.has_alpha?
    image.bands == cut.bands - 1 ? image.cast(cut.format) : nil
  end
  private_class_method :plain_colours
end
