# frozen_string_literal: true

# A world's pocket history (Chronicle): its seed and the GM's kept families
# on the world; a past on each atlas place; and a mark on what the history
# wrote into the codex, cast and fronts, so it can be rewritten or taken out.
class AddHistoryAndProvenance < ActiveRecord::Migration[8.1]
  def change
    add_column :worlds, :history, :json, default: {}, null: false
    add_column :world_places, :past, :json, default: {}, null: false
    add_column :codex_entries, :history_key, :string
    add_column :world_figures, :history_key, :string
    add_column :world_fronts, :history_key, :string
  end
end
