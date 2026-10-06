# frozen_string_literal: true

# Images and music are made elsewhere now (baible) and uploaded: nothing here
# records how an asset was made. The generation tables go (art direction,
# content types, each drawn thing's notes, LoRAs, model, seed and recipe,
# batches and their candidates), and with them the worlds' house style, the
# settings for ComfyUI, a mode's words for its picture and a generated
# track's description. A generated track keeps its audio, as an upload.
class AssetsAreUploaded < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # The candidates' images, never picked, go with them.
    blobs = select_values("SELECT blob_id FROM active_storage_attachments WHERE record_type = 'ArtCandidate'")
    execute "DELETE FROM active_storage_attachments WHERE record_type = 'ArtCandidate'"
    if blobs.any?
      execute "DELETE FROM active_storage_variant_records WHERE blob_id IN (#{blobs.join(', ')})"
      execute "DELETE FROM active_storage_blobs WHERE id IN (#{blobs.join(', ')})"
    end

    drop_table :art_candidates
    drop_table :art_batches
    drop_table :art_types
    drop_table :arts

    remove_column :worlds, :art_style
    remove_column :worlds, :art_negative
    remove_column :worlds, :art_loras
    remove_column :worlds, :art_model

    %i[comfy_url comfy_model rmbg_model draft_size draft_steps draft_denoise candidates].each { |column| remove_column :site_settings, column }

    remove_column :modes, :art

    execute "UPDATE tracks SET source = 'upload' WHERE source = 'generated'"
    %i[prompt lyrics seconds status error prompt_id started_at].each { |column| remove_column :tracks, column }
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
