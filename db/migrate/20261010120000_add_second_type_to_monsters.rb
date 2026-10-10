# frozen_string_literal: true

# A monster can be of two types, as in the games (a Viper is Poison and
# Grass): the chart's percents for both multiply (Battle::Types).
class AddSecondTypeToMonsters < ActiveRecord::Migration[8.1]
  def change
    add_column :monsters, :second_type, :string
  end
end
