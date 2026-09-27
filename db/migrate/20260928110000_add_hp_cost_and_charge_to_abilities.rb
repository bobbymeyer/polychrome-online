# frozen_string_literal: true

# Moves that cost HP (a percent of the user's max) and moves that take
# turns to go off (Battle::Resolver#wind_up).
class AddHpCostAndChargeToAbilities < ActiveRecord::Migration[8.1]
  def change
    add_column :abilities, :hp_cost, :integer, null: false, default: 0
    add_column :abilities, :charge, :integer, null: false, default: 0
  end
end
