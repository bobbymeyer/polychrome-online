# frozen_string_literal: true

# Local co-op: a campaign's join code (behind the QR code on the shared
# screen), and guest accounts for players who join with just a name.
class AddLocalCoop < ActiveRecord::Migration[8.1]
  def change
    add_column :campaigns, :join_code, :string
    add_index :campaigns, :join_code, unique: true
    add_column :users, :guest, :boolean, null: false, default: false
  end
end
