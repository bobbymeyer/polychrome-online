# frozen_string_literal: true

# The image model is chosen in layers like the prompt (§8): the world's, a
# content type's, an entry's own. The lowest layer that names one wins.
class LayeredArtModels < ActiveRecord::Migration[8.1]
  ENTRIES = %i[abilities characters encounter_tables generator_tables items jobs location_templates monsters npcs].freeze

  def change
    rename_column :worlds, :art_checkpoint, :art_model
    add_column :art_types, :model, :string
    ENTRIES.each { |table| add_column table, :art_model, :string }
  end
end
