# Generator tables are raw material for towns and dungeons; they don't get art.
class DropGeneratorTableArt < ActiveRecord::Migration[8.1]
  def up
    execute "DELETE FROM art_types WHERE kind = 'generator_table'"
  end

  def down; end
end
