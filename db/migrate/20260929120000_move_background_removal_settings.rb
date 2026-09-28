# frozen_string_literal: true

# Background removal is its own service now (Cutout), not a ComfyUI node:
# the Settings page names its address and model instead of a node.
class MoveBackgroundRemovalSettings < ActiveRecord::Migration[8.1]
  # Removing a column rebuilds the table in SQLite (spec/migrations_spec.rb).
  disable_ddl_transaction!

  def change
    add_column :site_settings, :cutout_url, :string
    add_column :site_settings, :cutout_model, :string
    remove_column :site_settings, :rembg_node, :string
  end
end
