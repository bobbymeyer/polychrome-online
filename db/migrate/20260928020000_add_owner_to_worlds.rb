# frozen_string_literal: true

# A world can belong to the GM who made it, so GMs run their own games
# without an admin. A world with no owner (the Base World) is the admins'.
class AddOwnerToWorlds < ActiveRecord::Migration[8.1]
  def change
    add_reference :worlds, :owner, foreign_key: { to_table: :users, on_delete: :nullify }
  end
end
