# frozen_string_literal: true

# What the party knows is its secrets, revealed; flags are the GM's own
# state. A flag the players could see becomes something the party knows
# ("Met the king: yes"), revealed when it was last set.
class FlagsAreTheGms < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    select_rows("SELECT campaign_id, key, value, updated_at FROM flags WHERE public = 1").each do |campaign_id, key, value, at|
      label = key.to_s.tr("_", " ").capitalize
      body = value.to_s.strip.empty? ? label : "#{label}: #{value}"
      execute <<~SQL
        INSERT INTO secrets (campaign_id, body, revealed_at, revealed_by, created_at, updated_at)
        VALUES (#{campaign_id.to_i}, #{connection.quote(body)}, #{connection.quote(at)}, 'The table', #{connection.quote(at)}, #{connection.quote(at)})
      SQL
    end
    remove_column :flags, :public
  end

  def down
    add_column :flags, :public, :boolean, default: false, null: false
  end
end
