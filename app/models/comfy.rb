# frozen_string_literal: true

# Talking to ComfyUI (docs/HANDOFF.md §8). Settings live in config/comfy.yml.
module Comfy
  class Error < StandardError; end

  def self.config
    Rails.configuration.x.comfy
  end

  # What ComfyUI has installed, for the pickers: remembered for a minute so a
  # page render doesn't wait on ComfyUI every time (or for long when it's down).
  # Remembered for a minute when ComfyUI answers; when it doesn't, only for
  # a few seconds, so starting it shows up on the next reload.
  def self.installed
    @installed = nil if @installed && @installed[:at] < (@installed[:reachable] ? 1.minute : 5.seconds).ago
    @installed ||= begin
      client = Client.new(timeout: 2)
      if client.reachable?
        { reachable: true, checkpoints: client.checkpoints, loras: client.loras, at: Time.current }
      else
        { reachable: false, checkpoints: [], loras: [], at: Time.current }
      end
    end
  end

  def self.forget_installed!
    @installed = nil
  end
end
