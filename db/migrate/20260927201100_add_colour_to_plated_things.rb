# A chosen plate colour (a Palette name); blank means "from its name".
class AddColourToPlatedThings < ActiveRecord::Migration[8.1]
  def change
    %i[monsters jobs npcs characters].each { |table| add_column table, :colour, :string }
  end
end
