# frozen_string_literal: true

# Talking to ComfyUI (docs/HANDOFF.md §8). Settings live in config/comfy.yml.
module Comfy
  class Error < StandardError; end

  def self.config
    Rails.configuration.x.comfy
  end

  # The backend the pipeline talks to (see Comfy::Client for its interface).
  def self.client(timeout: 30)
    Client.new(timeout: timeout)
  end

  # What ComfyUI has installed, for the pickers and the workflow preview.
  # Remembered for a minute when ComfyUI answers; when it doesn't, only for
  # a few seconds, so starting it shows up on the next reload.
  def self.capabilities
    @capabilities = nil if @capabilities && @capabilities_at < (@capabilities.reachable? ? 1.minute : 5.seconds).ago
    @capabilities ||= client(timeout: 3).capabilities.tap { @capabilities_at = Time.current }
  end

  def self.forget_capabilities!
    @capabilities = nil
  end
end
