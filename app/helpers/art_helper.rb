# frozen_string_literal: true

module ArtHelper
  # A LoRA stack, in order, switched-off ones struck through (§8).
  def lora_stack(loras)
    return "none" if loras.empty?

    safe_join(loras.map do |lora|
      text = "#{lora['name']} #{lora['strength']}"
      lora.fetch("on", true) && !lora["strength"].to_f.zero? ? text : tag.s(text, title: "switched off")
    end, " · ")
  end
end
