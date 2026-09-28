# frozen_string_literal: true

# How rough drafts are, how much "made properly" changes them, and how many
# candidates a batch makes, set on the Settings page (SiteSetting).
class AddDraftSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :site_settings, :draft_size, :integer
    add_column :site_settings, :draft_steps, :integer
    add_column :site_settings, :draft_denoise, :float
    add_column :site_settings, :candidates, :integer
  end
end
