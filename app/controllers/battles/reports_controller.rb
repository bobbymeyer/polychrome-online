# frozen_string_literal: true

# A battle's numbers, for the GM balancing it (Battle::Report): what each
# unit dealt, took and used, round by round. The GM's, since it shows the
# enemies' HP.
class Battles::ReportsController < ApplicationController
  include BattleSeat

  before_action :set_battle

  def show
    return forbid unless battle_gm?

    @report = @battle.report
  end
end
