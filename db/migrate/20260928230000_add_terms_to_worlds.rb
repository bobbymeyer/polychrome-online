# frozen_string_literal: true

# A setting's own words over the game's fixed ones (World#word): what money
# is called, HP and MP, the stats, the town services (and which it has at
# all), the statuses. The mechanics underneath don't change.
class AddTermsToWorlds < ActiveRecord::Migration[8.1]
  def change
    add_column :worlds, :terms, :json, null: false, default: {}
  end
end
