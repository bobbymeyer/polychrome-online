# frozen_string_literal: true

# Talking to ComfyUI (docs/HANDOFF.md §8). Settings live in config/comfy.yml.
module Comfy
  class Error < StandardError; end

  def self.config
    Rails.configuration.x.comfy
  end

  # What ComfyUI has installed, for the pickers: remembered for a minute so a
  # page render doesn't wait on ComfyUI every time (or for long when it's down).
  def self.installed
    @installed = nil if @installed && @installed[:at] < 1.minute.ago
    @installed ||= begin
      client = Client.new(timeout: 2)
      { checkpoints: client.checkpoints, loras: client.loras, at: Time.current }
    end
  end

  def self.forget_installed!
    @installed = nil
  end
end
