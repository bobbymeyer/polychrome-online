# frozen_string_literal: true

# Reads the per-expression portrait fields (app/views/portraits/_fields).
module PortraitUploads
  extend ActiveSupport::Concern

  private

  def portrait_params
    raw = params.fetch(:portraits, {}).permit(images: Portrait::EXPRESSIONS, remove: [])
    { uploads: raw[:images]&.to_h || {}, removals: Array(raw[:remove]) & Portrait::EXPRESSIONS }
  end
end
