# frozen_string_literal: true

# Who waits in a dungeon's boss room.
class Locations::BossesController < ApplicationController
  include LocationScoped

  before_action :require_table_gm

  def update
    boss = params.expect(boss: %i[monster count])
    placed = boss[:monster].present? && boss[:count].to_i.positive?
    @location.place_boss!(placed ? { boss[:monster] => boss[:count] } : {})
    back placed ? "Boss placed." : "The boss is back to what was rolled."
  end
end
