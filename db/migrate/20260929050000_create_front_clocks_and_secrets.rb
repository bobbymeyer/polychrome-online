# frozen_string_literal: true

# A front's clocks and secrets were JSON on the front, naming places and
# people by ids nothing checked. They're rows now (FrontClock,
# FrontSecret), and a place or person taken off the atlas or out of the cast
# lets go of them.
class CreateFrontClocksAndSecrets < ActiveRecord::Migration[8.1]
  # Removing a column rebuilds the table in SQLite, and inside a transaction
  # SQLite can't switch foreign keys off: the rebuild would fire ON DELETE
  # actions elsewhere (a character's choice picks cascade away). Outside
  # one, Rails switches them off for the rebuild.
  disable_ddl_transaction!

  class Front < ActiveRecord::Base
    self.table_name = "world_fronts"
  end

  def up
    create_table :front_clocks do |t|
      t.references :world_front, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :segments, default: 6, null: false
      t.json :triggers, default: [], null: false
      t.text :full_line
      t.boolean :public, default: false, null: false
      t.references :place, foreign_key: { to_table: :world_places, on_delete: :nullify }
      t.string :mode_name
      t.text :mode_line
      t.text :mode_description
      t.timestamps
    end
    create_table :front_secrets do |t|
      t.references :world_front, null: false, foreign_key: true
      t.text :body, null: false
      t.references :place, foreign_key: { to_table: :world_places, on_delete: :nullify }
      t.references :figure, foreign_key: { to_table: :world_figures, on_delete: :nullify }
      t.timestamps
    end

    Front.find_each do |front|
      Array(front.clocks).each do |c|
        insert(:front_clocks, world_front_id: front.id, name: c["name"], segments: c["segments"] || 6, triggers: Array(c["triggers"]).to_json,
                              full_line: c["full_line"], public: c["public"] ? true : false, place_id: known(:world_places, c["place_id"]),
                              mode_name: c["mode_name"], mode_line: c["mode_line"], mode_description: c["mode_description"])
      end
      Array(front.secrets).each do |s|
        insert(:front_secrets, world_front_id: front.id, body: s["body"], place_id: known(:world_places, s["place_id"]),
                               figure_id: known(:world_figures, s["figure_id"]))
      end
    end

    remove_column :world_fronts, :clocks
    remove_column :world_fronts, :secrets
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  # The id, if it still names something.
  def known(table, id)
    id && select_value("SELECT id FROM #{table} WHERE id = #{id.to_i}")
  end

  def insert(table, **values)
    now = connection.quote(Time.current)
    columns = values.keys.join(", ")
    execute "INSERT INTO #{table} (#{columns}, created_at, updated_at) VALUES (#{values.values.map { |v| connection.quote(v) }.join(', ')}, #{now}, #{now})"
  end
end
