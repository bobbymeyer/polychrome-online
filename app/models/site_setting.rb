# frozen_string_literal: true

# The app's own settings, one row, set by an admin on the Settings page:
# where ComfyUI and the language model answer, and their default models.
# Anything left blank falls back to the environment (config/comfy.yml,
# config/llm.yml). Only addresses and names live here: a token, a header
# or a password in a URL stays in the environment, never in the database.
class SiteSetting < ApplicationRecord
  URLS = %i[comfy_url llm_url].freeze
  FIELDS = %i[comfy_url comfy_model rembg_node llm_url llm_model].freeze

  normalizes(*FIELDS, with: ->(value) { value.to_s.strip.presence })

  validate :urls_are_plain_addresses

  after_commit { self.class.forget! }

  # The row, remembered for a few seconds so every page doesn't ask the
  # database (and other app processes pick up a change quickly).
  def self.current
    @current = nil if @current_at && @current_at < 5.seconds.ago
    @current ||= (first || new).tap { @current_at = Time.current }
  rescue ActiveRecord::StatementInvalid
    new # before the table exists (a fresh deploy mid-migration)
  end

  def self.forget!
    @current = nil
  end

  # The settings that override the environment's, for Comfy.config.
  def comfy_overrides
    { url: comfy_url, model: comfy_model, rembg_node: rembg_node }.compact
  end

  def llm_overrides
    { url: llm_url, model: llm_model }.compact
  end

  private

  def urls_are_plain_addresses
    URLS.each do |field|
      value = self[field] or next
      uri = URI.parse(value) rescue nil
      if !uri.is_a?(URI::HTTP) || uri.host.blank?
        errors.add(field, "must be an http:// or https:// address")
      elsif uri.userinfo
        errors.add(field, "can't hold a user or password: put those in the environment (COMFY_URL or LLM_URL), which never goes in the database")
      end
    end
  end
end
