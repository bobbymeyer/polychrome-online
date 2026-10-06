# frozen_string_literal: true

# A fight played out many times before anyone plays it, for the GM balancing
# the game (BattleSimulation): pick who fights and what they face, and see how
# it tends to go, run by run and move by move. A plain GET form, so a
# simulation's address can be kept and shared.
class Campaigns::SimulationsController < Campaigns::BaseController
  before_action :require_campaign_gm

  def show
    @simulation = BattleSimulation.new(@campaign, **choices)
  end

  private

  def choices
    raw = params.fetch(:simulation, ActionController::Parameters.new)
                .permit(:table, :runs, :tactics, :rested, characters: [], encounter: [ %i[monster count] ])
    encounter = JsonCasting.rows(raw[:encounter]).each_with_object(Hash.new(0)) do |row, counts|
      counts[row["monster"]] += row["count"].to_i if row["monster"].present?
    end
    {
      character_ids: raw[:characters], encounter: encounter, table: @world.encounter_tables.find_by(slug: raw[:table].presence),
      runs: raw.fetch(:runs, BattleSimulation::RUNS), tactics: raw[:tactics], rested: raw.fetch(:rested, "1") == "1"
    }
  end
end
