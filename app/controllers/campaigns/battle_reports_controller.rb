# frozen_string_literal: true

# Every battle the campaign has fought, its numbers together (Battle::Report.across):
# each fight in a line, and each kind of fighter and each move over all of
# them. The GM's, like each battle's own report. As CSV, a table a file
# (BattleReportCsv).
class Campaigns::BattleReportsController < Campaigns::BaseController
  before_action :require_campaign_gm

  def show
    battles = @campaign.battles.includes(:battle_events).order(created_at: :desc, id: :desc)
    @across = Battle::Report.across(battles.map do |battle|
      { "battle" => { "id" => battle.id, "name" => battle.name, "boss" => battle.boss, "fought_on" => battle.created_at.to_date }, "report" => battle.report }
    end)
    respond_to do |format|
      format.html
      format.csv do
        table = BattleReportCsv::CAMPAIGN_TABLES.include?(params[:table]) ? params[:table] : BattleReportCsv::CAMPAIGN_TABLES.first
        send_data BattleReportCsv.campaign(@across, @world, table: table), type: :csv, filename: "#{@campaign.name.parameterize}-#{table}.csv"
      end
    end
  end
end
