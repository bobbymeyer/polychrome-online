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

ActiveRecord::Schema[8.1].define(version: 2026_09_26_190000) do
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
    t.index ["campaign_id"], name: "index_battles_on_campaign_id"
    t.index ["world_id"], name: "index_battles_on_world_id"
  end

  create_table "campaigns", force: :cascade do |t|
    t.integer "world_id", null: false
    t.string "name", null: false
    t.integer "gil", default: 0, null: false
    t.integer "world_version"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.index ["campaign_id"], name: "index_characters_on_campaign_id"
    t.index ["job_id"], name: "index_characters_on_job_id"
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
    t.index ["world_id", "slug"], name: "index_jobs_on_world_id_and_slug", unique: true
    t.index ["world_id"], name: "index_jobs_on_world_id"
  end

  create_table "monsters", force: :cascade do |t|
    t.integer "world_id", null: false
    t.string "slug", null: false
    t.string "name", null: false
    t.integer "level", default: 1, null: false
    t.json "stats", default: {}, null: false
    t.json "elements", default: {}, null: false
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
    t.index ["world_id", "slug"], name: "index_monsters_on_world_id_and_slug", unique: true
    t.index ["world_id"], name: "index_monsters_on_world_id"
  end

  create_table "worlds", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_worlds_on_slug", unique: true
  end

  add_foreign_key "abilities", "worlds"
  add_foreign_key "ability_slots", "abilities"
  add_foreign_key "ability_slots", "characters"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "battle_actions", "battles"
  add_foreign_key "battle_events", "battle_actions"
  add_foreign_key "battle_events", "battles"
  add_foreign_key "battles", "campaigns"
  add_foreign_key "battles", "worlds"
  add_foreign_key "campaigns", "worlds"
  add_foreign_key "character_jobs", "characters"
  add_foreign_key "character_jobs", "jobs"
  add_foreign_key "characters", "campaigns"
  add_foreign_key "characters", "jobs"
  add_foreign_key "equipment_slots", "characters"
  add_foreign_key "equipment_slots", "items"
  add_foreign_key "inventories", "campaigns"
  add_foreign_key "inventories", "items"
  add_foreign_key "items", "worlds"
  add_foreign_key "job_levels", "abilities"
  add_foreign_key "job_levels", "jobs"
  add_foreign_key "jobs", "worlds"
  add_foreign_key "monsters", "worlds"
end
