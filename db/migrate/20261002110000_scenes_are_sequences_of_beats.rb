# frozen_string_literal: true

# A scene was one script and one ending. It is a sequence of beats now
# (Beat): each with who speaks and what they say, what the stage shows
# behind them (a place, a panel made for the beat, black, or what was
# there), who stands on the stage, and a cue or a change of music. The GM
# steps through them at the table (Scene#start!, #advance!), so a scene
# knows where it is (cursor) and whether it's running on its own (auto),
# and the campaign knows which scene is on its stage. Scripts already
# written become beats, one a line; the script column stays as the way to
# add lines in bulk.
class ScenesAreSequencesOfBeats < ActiveRecord::Migration[8.1]
  disable_ddl_transaction! # the way down removes columns (spec/migrations_spec.rb)

  def up
    create_table :beats do |t|
      t.references :scene, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :kind, null: false, default: "say"
      t.string :speaker_type
      t.integer :speaker_id
      t.string :expression
      t.text :text
      t.string :backdrop, null: false, default: "keep"
      t.references :map_node, foreign_key: true
      t.json :figures, null: false, default: []
      t.string :cue
      t.string :music
      t.json :options, null: false, default: []
      t.string :flag_key
      t.timestamps
    end
    add_index :beats, %i[scene_id position]
    add_column :scenes, :cursor, :integer
    add_column :scenes, :auto, :boolean, null: false, default: false
    add_column :campaigns, :staged_scene_id, :integer

    # Each written scene's lines become its beats.
    Scene.reset_column_information
    Scene.find_each do |scene|
      next if scene.script.blank?

      scene.import_script!
    end
  end

  def down
    remove_column :campaigns, :staged_scene_id
    remove_column :scenes, :auto
    remove_column :scenes, :cursor
    drop_table :beats
  end
end
