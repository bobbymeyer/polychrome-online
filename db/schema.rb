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

ActiveRecord::Schema[8.1].define(version: 2026_09_26_150000) do
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
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "items", "worlds"
  add_foreign_key "job_levels", "abilities"
  add_foreign_key "job_levels", "jobs"
  add_foreign_key "jobs", "worlds"
  add_foreign_key "monsters", "worlds"
end
