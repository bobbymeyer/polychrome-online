# frozen_string_literal: true

# A new campaign was dealt every world's fronts, not only its own world's
# (WorldFront.undealt_in). Take back the clocks and secrets that came from
# another world's fronts; talk that was going round about such a secret
# stays, as talk.
class TakeBackFrontsDealtFromOtherWorlds < ActiveRecord::Migration[8.1]
  FOREIGN = <<~SQL.squish
    JOIN campaigns ON campaigns.id = %<table>s.campaign_id
    JOIN world_fronts ON world_fronts.id = %<table>s.world_front_id
    WHERE world_fronts.world_id <> campaigns.world_id
  SQL

  def up
    secrets = "SELECT secrets.id FROM secrets #{format(FOREIGN, table: 'secrets')}"
    execute "UPDATE rumours SET secret_id = NULL WHERE secret_id IN (#{secrets})"
    execute "DELETE FROM secrets WHERE id IN (#{secrets})"
    execute "DELETE FROM clocks WHERE id IN (SELECT clocks.id FROM clocks #{format(FOREIGN, table: 'clocks')})"
  end

  def down; end
end
