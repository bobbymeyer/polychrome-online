# frozen_string_literal: true

# Background removal moves into ComfyUI (Cutout): no remover's address, and
# the model is ComfyUI-RMBG's (a rembg name like isnet-anime means nothing
# there, so it starts blank).
class BackgroundRemovalInComfy < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    remove_column :site_settings, :cutout_url, :string
    remove_column :site_settings, :cutout_model, :string
    add_column :site_settings, :rmbg_model, :string
  end
end
