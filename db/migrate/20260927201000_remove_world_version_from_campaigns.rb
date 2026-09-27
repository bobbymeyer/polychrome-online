# Worlds are live (docs/HANDOFF.md §9.8, decided): campaigns read the books as
# they are now, so there is no world version to pin.
class RemoveWorldVersionFromCampaigns < ActiveRecord::Migration[8.1]
  def change
    remove_column :campaigns, :world_version, :integer
  end
end
