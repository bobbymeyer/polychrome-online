# frozen_string_literal: true

# Characters and their jobs (docs/HANDOFF.md §4, campaign layer). Campaigns
# arrive here as the minimum characters need to live in; flags, diffs and
# the edition tooling come with build step 8.
class CreateCharacters < ActiveRecord::Migration[8.1]
  def change
    create_table :campaigns do |t|
      t.references :world, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :gil, null: false, default: 0
      # §9.8: campaigns will pin a world version and upgrade explicitly.
      # The column exists now; editions and the upgrade tooling don't yet.
      t.integer :world_version
      t.timestamps
    end

    create_table :characters do |t|
      t.references :campaign, null: false, foreign_key: true
      t.references :job, null: false, foreign_key: true
      t.string :name, null: false
      t.string :player_name
      t.integer :exp, null: false, default: 0
      t.integer :level, null: false, default: 1
      # Current HP/MP between battles; nil means full.
      t.integer :hp
      t.integer :mp
      t.timestamps
    end

    create_table :character_jobs do |t|
      t.references :character, null: false, foreign_key: true
      t.references :job, null: false, foreign_key: true
      t.integer :abp, null: false, default: 0
      t.integer :level, null: false, default: 0
      t.timestamps
      t.index %i[character_id job_id], unique: true
    end

    # Cross-job abilities equipped into the current job's free slots.
    create_table :ability_slots do |t|
      t.references :character, null: false, foreign_key: true
      t.references :ability, null: false, foreign_key: true
      t.integer :position, null: false
      t.timestamps
      t.index %i[character_id position], unique: true
    end

    create_table :equipment_slots do |t|
      t.references :character, null: false, foreign_key: true
      t.references :item, null: false, foreign_key: true
      t.string :slot, null: false
      t.timestamps
      t.index %i[character_id slot], unique: true
    end

    # The party's shared bag: items not currently equipped.
    create_table :inventories do |t|
      t.references :campaign, null: false, foreign_key: true
      t.references :item, null: false, foreign_key: true
      t.integer :quantity, null: false, default: 0
      t.timestamps
      t.index %i[campaign_id item_id], unique: true
    end

    # FF5: most jobs have one free ability slot; the Freelancer has two.
    add_column :jobs, :ability_slots, :integer, null: false, default: 1

    add_reference :battles, :campaign, foreign_key: true
    # What the battle's end did to the party: rewards, level-ups, learned
    # abilities. Written once, by BattleRecord#settle!.
    add_column :battles, :settlement, :json
  end
end
