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
module Comfy
  module BackgroundRemoval
    module_function

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
