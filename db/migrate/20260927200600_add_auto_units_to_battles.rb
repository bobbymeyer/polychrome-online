class AddAutoUnitsToBattles < ActiveRecord::Migration[8.1]
  def change
    add_column :battles, :auto_units, :json, null: false, default: []
  end
end
