# frozen_string_literal: true

# Every battle the campaign has fought, its numbers together (Battle::Report.across):
# each fight in a line, and each kind of fighter and each move over all of
# them. The GM's, like each battle's own report.
class Campaigns::BattleReportsController < Campaigns::BaseController
  before_action :require_campaign_gm

  def show
    battles = @campaign.battles.includes(:battle_events).order(created_at: :desc, id: :desc)
    @across = Battle::Report.across(battles.map do |battle|
      { "battle" => { "id" => battle.id, "name" => battle.name, "boss" => battle.boss, "fought_on" => battle.created_at.to_date }, "report" => battle.report }
    end)
  end
end
