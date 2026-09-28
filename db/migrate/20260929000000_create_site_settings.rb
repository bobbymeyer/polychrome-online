# frozen_string_literal: true

# Where the app finds ComfyUI and the language model, set by an admin in the
# app (SiteSetting). Blank falls back to the environment. No secrets: tokens
# and headers stay in the environment.
class CreateSiteSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :site_settings do |t|
      t.string :comfy_url
      t.string :comfy_model
      t.string :rembg_node
      t.string :llm_url
      t.string :llm_model
      t.timestamps
    end
  end
end
