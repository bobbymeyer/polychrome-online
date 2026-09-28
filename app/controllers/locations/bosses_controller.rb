# frozen_string_literal: true

# Who waits in a dungeon's boss room.
class Locations::BossesController < ApplicationController
  include LocationScoped

  before_action :require_gm

  def update
    boss = params.expect(boss: %i[monster count])
    @location.place_boss!(boss[:monster].present? ? { boss[:monster] => boss[:count] } : {})
    back boss[:monster].present? ? "Boss placed." : "The boss is back to what was rolled."
  end
end
