# frozen_string_literal: true

# Builds a ComfyUI workflow graph (API format) from a composed recipe, instead
# of filling in a fixed template: checkpoint, then one LoraLoader per LoRA in
# the recipe, chained, then the prompts, sampler, decode, an optional
# background-removal node, and SaveImage. Pure: data in, data out.
module Comfy
  module Graph
    module_function

    # recipe: "checkpoint", "loras" [{ "name", "strength" }], "positive",
    #         "negative", "width", "height", "transparent"
    # settings: "sampler", "scheduler", "steps", "cfg", "rembg_node", "rembg_input"
    def build(recipe, seed:, prefix:, settings: {})
      graph = {}
      id = 0
      add = ->(class_type, inputs) { graph[(id += 1).to_s] = { "class_type" => class_type, "inputs" => inputs }; id.to_s }

      checkpoint = add.("CheckpointLoaderSimple", { "ckpt_name" => recipe.fetch("checkpoint") })
      model = [ checkpoint, 0 ]
      clip = [ checkpoint, 1 ]
      Array(recipe["loras"]).each do |lora|
        loader = add.("LoraLoader", { "lora_name" => lora["name"], "strength_model" => lora["strength"].to_f,
                                      "strength_clip" => lora["strength"].to_f, "model" => model, "clip" => clip })
        model = [ loader, 0 ]
        clip = [ loader, 1 ]
      end

      positive = add.("CLIPTextEncode", { "text" => recipe["positive"].to_s, "clip" => clip })
      negative = add.("CLIPTextEncode", { "text" => recipe["negative"].to_s, "clip" => clip })
      latent = add.("EmptyLatentImage", { "width" => recipe.fetch("width").to_i, "height" => recipe.fetch("height").to_i, "batch_size" => 1 })
      sampler = add.("KSampler", {
        "seed" => seed, "steps" => settings.fetch("steps", 25).to_i, "cfg" => settings.fetch("cfg", 6.5).to_f,
        "sampler_name" => settings.fetch("sampler", "euler").to_s, "scheduler" => settings.fetch("scheduler", "normal").to_s,
        "denoise" => 1, "model" => model, "positive" => [ positive, 0 ], "negative" => [ negative, 0 ], "latent_image" => [ latent, 0 ]
      })
      image = [ add.("VAEDecode", { "samples" => [ sampler, 0 ], "vae" => [ checkpoint, 2 ] }), 0 ]

      rembg = settings["rembg_node"].presence
      if recipe["transparent"] && rembg
        image = [ add.(rembg, { settings.fetch("rembg_input", "image").presence || "image" => image }), 0 ]
      end

      add.("SaveImage", { "filename_prefix" => prefix, "images" => image })
      graph
    end
  end
end
