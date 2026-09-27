# A monster can be a boss, with a line it says before the fight; a battle
# knows whether it's a boss fight (for its entrance, music and ending).
class AddBosses < ActiveRecord::Migration[8.1]
  def change
    add_column :monsters, :boss, :boolean, null: false, default: false
    add_column :monsters, :boss_line, :text
    add_column :battles, :boss, :boolean, null: false, default: false
  end
end
