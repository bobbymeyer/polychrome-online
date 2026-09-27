# frozen_string_literal: true

# Types and skills belong to the setting: each world has its own list, the
# chart between its types, the type of each terrain, and the skills its
# checks are made with. Existing worlds get the base world's.
class AddTypesAndSkillsToWorlds < ActiveRecord::Migration[8.1]
  def up
    add_column :worlds, :damage_types, :json, null: false, default: []
    add_column :worlds, :terrain_types, :json, null: false, default: {}
    add_column :worlds, :skills, :json, null: false, default: []
    add_column :jobs, :skills, :json, null: false, default: []

    World.reset_column_information
    World.find_each do |world|
      world.update_columns(damage_types: TypeChart.default_rows, terrain_types: TypeChart::DEFAULT_TERRAIN,
                           skills: World::DEFAULT_SKILLS)
    end
  end

  def down
    remove_column :jobs, :skills
    remove_column :worlds, :skills
    remove_column :worlds, :terrain_types
    remove_column :worlds, :damage_types
  end
end
