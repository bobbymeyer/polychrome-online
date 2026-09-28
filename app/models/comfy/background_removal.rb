# frozen_string_literal: true

# Taking the background off a generated image, with whatever removal node
# this ComfyUI has. There's no such node in ComfyUI itself, and each custom
# pack names its node and inputs its own way, so the candidates are listed
# in config (comfy.yml `background_removal`, COMFY_REMBG_NODE first) and
# each is wired from the server's own description of it (/object_info): the
# image goes into its IMAGE input, every other required input takes its
# default (or the value config gives), and its first IMAGE output goes on.
# A node that needs something else plugged in (a model loader) is passed over.
#
# Whether it worked is checked on the image itself (ArtCandidate#transparent).
#
# A removal model takes whatever looks like the background, and on flat art
# drawn on white that includes the white inside the subject: a belly, a
# face, a sail. So the result is mended (#keep_interior): only what's
# transparent and connected to the edge of the picture is background; a
# transparent patch enclosed by the subject is put back, from the picture as
# rendered (saved alongside, with PLAIN on its name). The cost: a gap that
# really is background but is closed in (an arm on a hip) is filled too.
module Comfy
  module BackgroundRemoval
    PLAIN = "-plain"
    # Alpha under this counts as removed.
    CLEAR = 128

    module_function

    # Of a finished prompt's images: [the removed one, the plain one or nil].
    def split(images)
      plain = images.find { |image| image["filename"].to_s.include?("#{PLAIN}_") }
      [ (images - [ plain ]).first, plain ]
    end

    # The removed image with the holes inside the subject made opaque again,
    # in the plain image's colours when there is one. PNG bytes in and out.
    def keep_interior(removed, plain = nil)
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

    def plain_colours(plain, cut)
      return unless plain

      image = Vips::Image.new_from_buffer(plain, "")
      return unless image.width == cut.width && image.height == cut.height

      image = image.extract_band(0, n: image.bands - 1) if image.has_alpha?
      image.bands == cut.bands - 1 ? image : nil
    end

    # [{ "node", "image_input", "inputs" => { name => value } }] in order of
    # preference: COMFY_REMBG_NODE first, then comfy.yml's list.
    def candidates
      pinned = Comfy.config[:rembg_node].presence
      listed = Array(Comfy.config[:background_removal]).map { |c| c.to_h.deep_stringify_keys }
      (pinned ? [ { "node" => pinned, "image_input" => Comfy.config[:rembg_input].presence } ] : []) + listed
    end

    def node_names = candidates.map { |c| c["node"] }.uniq

    # The first candidate this server has and that can be wired alone.
    def pick(capabilities)
      candidates.each do |candidate|
        wiring = wiring(candidate, capabilities)
        return wiring if wiring
      end
      nil
    end

    # { node:, image_input:, inputs:, output: } or nil.
    def wiring(candidate, capabilities)
      spec = capabilities.info(candidate["node"]) or return nil
      required = spec.dig("input", "required").to_h
      image_input = candidate["image_input"] if required.key?(candidate["image_input"].to_s)
      image_input ||= required.find { |_, s| Array(s).first == "IMAGE" }&.first
      return nil unless image_input

      inputs = {}
      required.except(image_input).each do |name, s|
        given = candidate.dig("inputs", name)
        value = given.nil? ? default_for(s) : given
        return nil if value.nil? # needs a link we can't make
        inputs[name] = value
      end
      output = Array(spec["output"]).index("IMAGE") or return nil
      { node: candidate["node"], image_input: image_input, inputs: inputs, output: output }
    end

    # A required input's default, from how ComfyUI describes it.
    def default_for(spec)
      type, options = Array(spec)
      options = options.to_h
      case type
      when Array then options.key?("default") ? options["default"] : type.first
      when "COMBO" then options["default"] || Array(options["options"]).first
      when "INT", "FLOAT", "BOOLEAN", "STRING" then options.key?("default") ? options["default"] : { "INT" => 0, "FLOAT" => 0.0, "BOOLEAN" => false, "STRING" => "" }[type]
      end
    end

    # Adds the node after `image`; returns the new image link.
    def wire(add, image, wiring)
      [ add.(wiring[:node], wiring[:inputs].merge(wiring[:image_input] => image)), wiring[:output] ]
    end

    # Does a PNG have an alpha channel? (colour types 4 and 6, or a tRNS chunk)
    def png_alpha?(bytes)
      bytes = bytes.to_s.b
      return false unless bytes.start_with?("\x89PNG".b) && bytes.bytesize > 26

      [ 4, 6 ].include?(bytes.getbyte(25)) || bytes.include?("tRNS".b)
    end
  end
end
