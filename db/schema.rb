# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_28_060000) do
  create_table "abilities", force: :cascade do |t|
    t.integer "world_id", null: false
    t.string "slug", null: false
    t.string "name", null: false
    t.string "kind", default: "skill", null: false
    t.string "target", null: false
    t.integer "mp_cost", default: 0, null: false
    t.json "effects", default: [], null: false
    t.string "gesture"
    t.text "description"
    t.json "variant", default: {}, null: false
    t.integer "image_seed"
    t.text "image_prompt"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "art_notes"
    t.json "art_loras", default: [], null: false
    t.json "image_recipe"
    t.index ["world_id", "slug"], name: "index_abilities_on_world_id_and_slug", unique: true
    t.index ["world_id"], name: "index_abilities_on_world_id"
  end

  create_table "ability_slots", force: :cascade do |t|
    t.integer "character_id", null: false
    t.integer "ability_id", null: false
    t.integer "position", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ability_id"], name: "index_ability_slots_on_ability_id"
    t.index ["character_id", "position"], name: "index_ability_slots_on_character_id_and_position", unique: true
    t.index ["character_id"], name: "index_ability_slots_on_character_id"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "art_batches", force: :cascade do |t|
    t.integer "world_id", null: false
    t.string "entry_type", null: false
    t.integer "entry_id", null: false
    t.json "recipe", default: {}, null: false
    t.string "status", default: "queued", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entry_type", "entry_id"], name: "index_art_batches_on_entry"
    t.index ["world_id"], name: "index_art_batches_on_world_id"
  end

  create_table "art_candidates", force: :cascade do |t|
    t.integer "art_batch_id", null: false
    t.integer "position", null: false
    t.integer "seed", null: false
    t.string "comfy_prompt_id"
    t.string "status", default: "queued", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["art_batch_id"], name: "index_art_candidates_on_art_batch_id"
  end

  create_table "art_types", force: :cascade do |t|
    t.integer "world_id", null: false
    t.string "kind", null: false
    t.text "prompt"
    t.text "negative"
    t.json "loras", default: [], null: false
    t.integer "width", default: 1024, null: false
    t.integer "height", default: 1024, null: false
    t.boolean "transparent", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["world_id", "kind"], name: "index_art_types_on_world_id_and_kind", unique: true
    t.index ["world_id"], name: "index_art_types_on_world_id"
  end

  create_table "battle_actions", force: :cascade do |t|
    t.integer "battle_id", null: false
    t.integer "position", null: false
    t.string "actor", null: false
    t.json "payload", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["battle_id", "position"], name: "index_battle_actions_on_battle_id_and_position", unique: true
    t.index ["battle_id"], name: "index_battle_actions_on_battle_id"
  end

  create_table "battle_events", force: :cascade do |t|
    t.integer "battle_id", null: false
    t.integer "battle_action_id", null: false
    t.integer "position", null: false
    t.string "kind", null: false
    t.json "payload", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["battle_action_id"], name: "index_battle_events_on_battle_action_id"
    t.index ["battle_id", "position"], name: "index_battle_events_on_battle_id_and_position", unique: true
    t.index ["battle_id"], name: "index_battle_events_on_battle_id"
  end

  create_table "battles", force: :cascade do |t|
    t.integer "world_id", null: false
    t.string "name", null: false
    t.integer "seed", null: false
    t.string "status", default: "input", null: false
    t.integer "round", default: 1, null: false
    t.json "initial_state", null: false
    t.json "state", null: false
    t.integer "input_seconds"
    t.datetime "deadline_at"
    t.integer "playback_speed", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "campaign_id"
    t.json "settlement"
    t.json "auto_units", default: [], null: false
    t.boolean "boss", default: false, null: false
    t.index ["campaign_id"], name: "index_battles_on_campaign_id"
    t.index ["world_id"], name: "index_battles_on_world_id"
  end

  create_table "campaigns", force: :cascade do |t|
    t.integer "world_id", null: false
    t.string "name", null: false
    t.integer "gil", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "current_node_id"
    t.integer "rng", default: 0, null: false
    t.json "pending_encounter"
    t.integer "gm_id"
    t.json "known_affinities", default: {}, null: false
    t.string "music"
    t.string "join_code"
    t.index ["current_node_id"], name: "index_campaigns_on_current_node_id"
    t.index ["gm_id"], name: "index_campaigns_on_gm_id"
    t.index ["join_code"], name: "index_campaigns_on_join_code", unique: true
    t.index ["world_id"], name: "index_campaigns_on_world_id"
  end

  create_table "character_jobs", force: :cascade do |t|
    t.integer "character_id", null: false
    t.integer "job_id", null: false
    t.integer "abp", default: 0, null: false
    t.integer "level", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["character_id", "job_id"], name: "index_character_jobs_on_character_id_and_job_id", unique: true
    t.index ["character_id"], name: "index_character_jobs_on_character_id"
    t.index ["job_id"], name: "index_character_jobs_on_job_id"
  end

  create_table "characters", force: :cascade do |t|
    t.integer "campaign_id", null: false
    t.integer "job_id", null: false
    t.string "name", null: false
    t.string "player_name"
    t.integer "exp", default: 0, null: false
    t.integer "level", default: 1, null: false
    t.integer "hp"
    t.integer "mp"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "art_notes"
    t.json "art_loras", default: [], null: false
    t.integer "user_id"
    t.string "colour"
    t.string "motive"
    t.index ["campaign_id"], name: "index_characters_on_campaign_id"
    t.index ["job_id"], name: "index_characters_on_job_id"
    t.index ["user_id"], name: "index_characters_on_user_id"
  end

  create_table "choice_picks", force: :cascade do |t|
    t.integer "message_id", null: false
    t.integer "character_id", null: false
    t.string "option", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["character_id"], name: "index_choice_picks_on_character_id"
    t.index ["message_id", "character_id"], name: "index_choice_picks_on_message_id_and_character_id", unique: true
    t.index ["message_id"], name: "index_choice_picks_on_message_id"
  end

  create_table "encounter_tables", force: :cascade do |t|
    t.integer "world_id", null: false
    t.string "slug", null: false
    t.string "name", null: false
    t.string "terrain", null: false
    t.integer "tier", default: 1, null: false
    t.json "entries", default: [], null: false
    t.text "description"
    t.json "variant", default: {}, null: false
    t.integer "image_seed"
    t.text "image_prompt"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "art_notes"
    t.json "art_loras", default: [], null: false
    t.json "image_recipe"
    t.index ["world_id", "slug"], name: "index_encounter_tables_on_world_id_and_slug", unique: true
    t.index ["world_id"], name: "index_encounter_tables_on_world_id"
  end

  create_table "equipment_slots", force: :cascade do |t|
    t.integer "character_id", null: false
    t.integer "item_id", null: false
    t.string "slot", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["character_id", "slot"], name: "index_equipment_slots_on_character_id_and_slot", unique: true
    t.index ["character_id"], name: "index_equipment_slots_on_character_id"
    t.index ["item_id"], name: "index_equipment_slots_on_item_id"
  end

  create_table "flags", force: :cascade do |t|
    t.integer "campaign_id", null: false
    t.string "key", null: false
    t.string "value", default: "", null: false
    t.text "note"
    t.boolean "public", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "key"], name: "index_flags_on_campaign_id_and_key", unique: true
    t.index ["campaign_id"], name: "index_flags_on_campaign_id"
  end

  create_table "generator_tables", force: :cascade do |t|
    t.integer "world_id", null: false
    t.string "slug", null: false
    t.string "name", null: false
    t.string "kind", null: false
    t.json "entries", default: [], null: false
    t.text "description"
    t.json "variant", default: {}, null: false
    t.integer "image_seed"
    t.text "image_prompt"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "art_notes"
    t.json "art_loras", default: [], null: false
    t.json "image_recipe"
    t.index ["world_id", "slug"], name: "index_generator_tables_on_world_id_and_slug", unique: true
    t.index ["world_id"], name: "index_generator_tables_on_world_id"
  end

  create_table "inventories", force: :cascade do |t|
    t.integer "campaign_id", null: false
    t.integer "item_id", null: false
    t.integer "quantity", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "item_id"], name: "index_inventories_on_campaign_id_and_item_id", unique: true
    t.index ["campaign_id"], name: "index_inventories_on_campaign_id"
    t.index ["item_id"], name: "index_inventories_on_item_id"
  end

  create_table "items", force: :cascade do |t|
    t.integer "world_id", null: false
    t.string "slug", null: false
    t.string "name", null: false
    t.string "category", null: false
    t.integer "price", default: 0, null: false
    t.json "stats", default: {}, null: false
    t.string "target"
    t.json "effects", default: [], null: false
    t.text "description"
    t.json "variant", default: {}, null: false
    t.integer "image_seed"
    t.text "image_prompt"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "art_notes"
    t.json "art_loras", default: [], null: false
    t.json "image_recipe"
    t.index ["world_id", "slug"], name: "index_items_on_world_id_and_slug", unique: true
    t.index ["world_id"], name: "index_items_on_world_id"
  end

  create_table "job_levels", force: :cascade do |t|
    t.integer "job_id", null: false
    t.integer "ability_id", null: false
    t.integer "level", null: false
    t.integer "abp", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ability_id"], name: "index_job_levels_on_ability_id"
    t.index ["job_id", "level"], name: "index_job_levels_on_job_id_and_level", unique: true
    t.index ["job_id"], name: "index_job_levels_on_job_id"
  end

  create_table "jobs", force: :cascade do |t|
    t.integer "world_id", null: false
    t.string "slug", null: false
    t.string "name", null: false
    t.json "stat_multipliers", default: {}, null: false
    t.json "equip_categories", default: [], null: false
    t.json "innates", default: [], null: false
    t.text "description"
    t.json "variant", default: {}, null: false
    t.integer "image_seed"
    t.text "image_prompt"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "ability_slots", default: 1, null: false
    t.text "art_notes"
    t.json "art_loras", default: [], null: false
    t.json "image_recipe"
    t.string "colour"
    t.string "desperation"
    t.index ["world_id", "slug"], name: "index_jobs_on_world_id_and_slug", unique: true
    t.index ["world_id"], name: "index_jobs_on_world_id"
  end

  create_table "location_templates", force: :cascade do |t|
    t.integer "world_id", null: false
    t.string "slug", null: false
    t.string "name", null: false
    t.string "kind", null: false
    t.json "config", default: {}, null: false
    t.integer "encounter_table_id"
    t.text "description"
    t.json "variant", default: {}, null: false
    t.integer "image_seed"
    t.text "image_prompt"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "art_notes"
    t.json "art_loras", default: [], null: false
    t.json "image_recipe"
    t.index ["encounter_table_id"], name: "index_location_templates_on_encounter_table_id"
    t.index ["world_id", "slug"], name: "index_location_templates_on_world_id_and_slug", unique: true
    t.index ["world_id"], name: "index_location_templates_on_world_id"
  end

  create_table "locations", force: :cascade do |t|
    t.integer "campaign_id", null: false
    t.integer "location_template_id", null: false
    t.integer "seed", null: false
    t.json "overrides", default: {}, null: false
    t.json "progress", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id"], name: "index_locations_on_campaign_id"
    t.index ["location_template_id"], name: "index_locations_on_location_template_id"
  end

  create_table "map_edges", force: :cascade do |t|
    t.integer "campaign_id", null: false
    t.integer "from_node_id", null: false
    t.integer "to_node_id", null: false
    t.string "state", default: "open", null: false
    t.integer "encounter_table_id"
    t.text "travel_event"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id"], name: "index_map_edges_on_campaign_id"
    t.index ["encounter_table_id"], name: "index_map_edges_on_encounter_table_id"
    t.index ["from_node_id"], name: "index_map_edges_on_from_node_id"
    t.index ["to_node_id"], name: "index_map_edges_on_to_node_id"
  end

  create_table "map_nodes", force: :cascade do |t|
    t.integer "campaign_id", null: false
    t.string "name", null: false
    t.string "kind", default: "field", null: false
    t.integer "x", null: false
    t.integer "y", null: false
    t.boolean "visible", default: false, null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "location_id"
    t.index ["campaign_id"], name: "index_map_nodes_on_campaign_id"
    t.index ["location_id"], name: "index_map_nodes_on_location_id"
  end

  create_table "messages", force: :cascade do |t|
    t.integer "campaign_id", null: false
    t.string "speaker_type"
    t.integer "speaker_id"
    t.integer "recipient_id"
    t.integer "battle_id"
    t.string "kind", default: "say", null: false
    t.string "scope", default: "table", null: false
    t.string "expression"
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "cue"
    t.json "options", default: [], null: false
    t.string "flag_key"
    t.string "settled"
    t.json "data", default: {}, null: false
    t.index ["battle_id"], name: "index_messages_on_battle_id"
    t.index ["campaign_id", "created_at"], name: "index_messages_on_campaign_id_and_created_at"
    t.index ["campaign_id"], name: "index_messages_on_campaign_id"
    t.index ["recipient_id"], name: "index_messages_on_recipient_id"
    t.index ["speaker_type", "speaker_id"], name: "index_messages_on_speaker"
  end

  create_table "monsters", force: :cascade do |t|
    t.integer "world_id", null: false
    t.string "slug", null: false
    t.string "name", null: false
    t.integer "level", default: 1, null: false
    t.json "stats", default: {}, null: false
    t.json "affinities", default: {}, null: false
    t.json "status_immune", default: [], null: false
    t.json "ai_script", default: [], null: false
    t.json "drops", default: [], null: false
    t.integer "exp", default: 0, null: false
    t.integer "gil", default: 0, null: false
    t.integer "abp", default: 0, null: false
    t.text "description"
    t.json "variant", default: {}, null: false
    t.integer "image_seed"
    t.text "image_prompt"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "art_notes"
    t.json "art_loras", default: [], null: false
    t.json "image_recipe"
    t.string "colour"
    t.boolean "boss", default: false, null: false
    t.text "boss_line"
    t.string "base_type", default: "normal", null: false
    t.index ["world_id", "slug"], name: "index_monsters_on_world_id_and_slug", unique: true
    t.index ["world_id"], name: "index_monsters_on_world_id"
  end

  create_table "npcs", force: :cascade do |t|
    t.integer "campaign_id", null: false
    t.string "name", null: false
    t.string "title"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "location_id"
    t.string "location_key"
    t.text "art_notes"
    t.json "art_loras", default: [], null: false
    t.string "colour"
    t.index ["campaign_id"], name: "index_npcs_on_campaign_id"
    t.index ["location_id"], name: "index_npcs_on_location_id"
  end

  create_table "portraits", force: :cascade do |t|
    t.string "owner_type", null: false
    t.integer "owner_id", null: false
    t.string "expression", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "image_seed"
    t.text "image_prompt"
    t.json "image_recipe"
    t.index ["owner_type", "owner_id", "expression"], name: "index_portraits_on_owner_type_and_owner_id_and_expression", unique: true
    t.index ["owner_type", "owner_id"], name: "index_portraits_on_owner"
  end

  create_table "scenes", force: :cascade do |t|
    t.integer "campaign_id", null: false
    t.string "name", null: false
    t.text "script"
    t.string "ending", default: "none", null: false
    t.json "encounter", default: {}, null: false
    t.integer "map_node_id"
    t.datetime "played_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id"], name: "index_scenes_on_campaign_id"
    t.index ["map_node_id"], name: "index_scenes_on_map_node_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name"
    t.boolean "admin", default: false, null: false
    t.boolean "guest", default: false, null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  create_table "worlds", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "art_style"
    t.text "art_negative"
    t.json "art_loras", default: [], null: false
    t.string "art_checkpoint"
    t.integer "owner_id"
    t.index ["owner_id"], name: "index_worlds_on_owner_id"
    t.index ["slug"], name: "index_worlds_on_slug", unique: true
  end

  add_foreign_key "abilities", "worlds"
  add_foreign_key "ability_slots", "abilities"
  add_foreign_key "ability_slots", "characters"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "art_batches", "worlds"
  add_foreign_key "art_candidates", "art_batches"
  add_foreign_key "art_types", "worlds"
  add_foreign_key "battle_actions", "battles"
  add_foreign_key "battle_events", "battle_actions"
  add_foreign_key "battle_events", "battles"
  add_foreign_key "battles", "campaigns"
  add_foreign_key "battles", "worlds"
  add_foreign_key "campaigns", "map_nodes", column: "current_node_id"
  add_foreign_key "campaigns", "users", column: "gm_id", on_delete: :nullify
  add_foreign_key "campaigns", "worlds"
  add_foreign_key "character_jobs", "characters"
  add_foreign_key "character_jobs", "jobs"
  add_foreign_key "characters", "campaigns"
  add_foreign_key "characters", "jobs"
  add_foreign_key "characters", "users", on_delete: :nullify
  add_foreign_key "choice_picks", "characters", on_delete: :cascade
  add_foreign_key "choice_picks", "messages", on_delete: :cascade
  add_foreign_key "encounter_tables", "worlds"
  add_foreign_key "equipment_slots", "characters"
  add_foreign_key "equipment_slots", "items"
  add_foreign_key "flags", "campaigns"
  add_foreign_key "generator_tables", "worlds"
  add_foreign_key "inventories", "campaigns"
  add_foreign_key "inventories", "items"
  add_foreign_key "items", "worlds"
  add_foreign_key "job_levels", "abilities"
  add_foreign_key "job_levels", "jobs"
  add_foreign_key "jobs", "worlds"
  add_foreign_key "location_templates", "encounter_tables"
  add_foreign_key "location_templates", "worlds"
  add_foreign_key "locations", "campaigns"
  add_foreign_key "locations", "location_templates"
  add_foreign_key "map_edges", "campaigns"
  add_foreign_key "map_edges", "encounter_tables"
  add_foreign_key "map_edges", "map_nodes", column: "from_node_id"
  add_foreign_key "map_edges", "map_nodes", column: "to_node_id"
  add_foreign_key "map_nodes", "campaigns"
  add_foreign_key "map_nodes", "locations"
  add_foreign_key "messages", "battles"
  add_foreign_key "messages", "campaigns"
  add_foreign_key "messages", "characters", column: "recipient_id"
  add_foreign_key "monsters", "worlds"
  add_foreign_key "npcs", "campaigns"
  add_foreign_key "npcs", "locations"
  add_foreign_key "scenes", "campaigns"
  add_foreign_key "scenes", "map_nodes", on_delete: :nullify
  add_foreign_key "sessions", "users"
  add_foreign_key "worlds", "users", column: "owner_id", on_delete: :nullify
end
