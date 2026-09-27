# frozen_string_literal: true

# An optional language model (config/llm.yml), reached over an
# OpenAI-compatible chat API. Used to write image prompts (PromptWriter);
# everything works without one.
module Llm
  class Error < StandardError; end

  def self.config
    Rails.configuration.x.llm
  end

  def self.enabled?
    config[:url].present?
  end

  def self.client
    Client.new
  end
end
