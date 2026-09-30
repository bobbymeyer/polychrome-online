# frozen_string_literal: true

# A deed is a rumour: what the party did, with the sway it carries, told
# from where it happened. The rumour a deed started takes its kind and day;
# a deed told nowhere (no place) becomes a rumour that never travels.
class DeedsAreRumours < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_column :rumours, :deed, :string
    add_column :rumours, :day, :integer
    select_rows("SELECT id, campaign_id, body, map_node_id, day, sway, kind, created_at FROM deeds").each do |id, campaign_id, body, node, day, sway, kind, at|
      told = select_value("SELECT id FROM rumours WHERE deed_id = #{id.to_i} ORDER BY id LIMIT 1")
      if told
        execute "UPDATE rumours SET deed = #{connection.quote(kind)}, day = #{day.to_i} WHERE id = #{told.to_i}"
      else
        execute <<~SQL
          INSERT INTO rumours (campaign_id, body, origin_id, sway, deed, day, created_at, updated_at)
          VALUES (#{campaign_id.to_i}, #{connection.quote(body)}, #{node ? node.to_i : 'NULL'}, #{sway.to_i}, #{connection.quote(kind)}, #{day.to_i},
                  #{connection.quote(at)}, #{connection.quote(at)})
        SQL
      end
    end
    remove_index :rumours, :deed_id
    remove_column :rumours, :deed_id
    drop_table :deeds
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
