# frozen_string_literal: true

# A clock can keep to the calendar's words, as modes and things to do do:
# "each new day, on Mondays", "each rest, in winter" (Clock#times).
class AddTimesToClocks < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :clocks, :times, :json, default: [], null: false
  end
end
