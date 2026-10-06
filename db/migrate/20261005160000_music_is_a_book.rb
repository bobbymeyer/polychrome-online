# frozen_string_literal: true

# Music becomes a book of the world (Track): each track named, for a kind of
# scene or for the GM to call by name, and from an upload, a link (YouTube,
# Spotify) or ACE-Step in ComfyUI. The five tracks a world had attached to
# itself become its first tracks, keeping their files.
class MusicIsABook < ActiveRecord::Migration[8.1]
  def up
    create_table :tracks do |t|
      t.references :world, null: false, foreign_key: true
      t.string :name, null: false
      t.string :scene
      t.string :source, null: false, default: "upload"
      t.string :url
      t.text :prompt
      t.text :lyrics
      t.integer :seconds, null: false, default: 60
      t.string :status
      t.text :error
      t.string :prompt_id
      t.datetime :started_at
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    attachments = select_all("SELECT id, record_id, name FROM active_storage_attachments WHERE record_type = 'World' AND name LIKE 'music_%'")
    attachments.each_with_index do |row, i|
      scene = row["name"].delete_prefix("music_")
      now = Time.current.to_fs(:db)
      track_id = insert("INSERT INTO tracks (world_id, name, scene, source, position, created_at, updated_at) " \
                        "VALUES (#{row['record_id']}, #{quote(scene.capitalize)}, #{quote(scene)}, 'upload', #{i}, #{quote(now)}, #{quote(now)})")
      update("UPDATE active_storage_attachments SET record_type = 'Track', record_id = #{track_id}, name = 'audio' WHERE id = #{row['id']}")
    end
  end

  def down
    attachments = select_all("SELECT a.id, t.world_id, t.scene FROM active_storage_attachments a JOIN tracks t ON t.id = a.record_id " \
                             "WHERE a.record_type = 'Track' AND t.scene IS NOT NULL")
    attachments.group_by { |row| [ row["world_id"], row["scene"] ] }.each_value do |rows|
      row = rows.first
      update("UPDATE active_storage_attachments SET record_type = 'World', record_id = #{row['world_id']}, name = #{quote("music_#{row['scene']}")} WHERE id = #{row['id']}")
    end
    drop_table :tracks
  end
end
