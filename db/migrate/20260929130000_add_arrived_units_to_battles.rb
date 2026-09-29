# frozen_string_literal: true

# Who has reached a battle's screen: its first round's clock waits for them.
class AddArrivedUnitsToBattles < ActiveRecord::Migration[8.1]
  def change
    add_column :battles, :arrived_units, :json, default: [], null: false
  end
end
