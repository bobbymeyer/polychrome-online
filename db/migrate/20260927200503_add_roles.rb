# Accounts and what they may do. The first account is the admin (world-
# building, art, running any campaign); a campaign has a GM account; a
# character belongs to its player's account. Existing campaigns and
# characters have none yet: an admin runs them, and a character goes to the
# first player who sits in it.
class AddRoles < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :name, :string
    add_column :users, :admin, :boolean, null: false, default: false
    add_reference :campaigns, :gm, foreign_key: { to_table: :users, on_delete: :nullify }
    add_reference :characters, :user, foreign_key: { on_delete: :nullify }
  end
end
