# frozen_string_literal: true

class BattlesController < ApplicationController
  include BattleSeat
  include CampaignScoped

  # The battle form's fields (BattleSetup).
  FORM = [ :name, :seed, :escapable, :input_seconds, :terrain, { characters: [], antagonists: [], encounter: [ %i[monster count] ] } ].freeze

  before_action :set_campaign, only: %i[new create]
  before_action :require_campaign_gm, only: %i[new create]
  before_action :set_battle, only: :show

  # A battle is set up at the table, under the stage, once Battle is called
  # (Campaign::Controls): the old page's address calls it and goes there.
  def new
    @campaign.call_controls!("battle")
    redirect_to campaign_table_path(@campaign)
  end

  def create
    @battle = BattleSetup.new(@campaign, params.expect(battle: FORM)).start!
    take_seat("gm")
    redirect_to battle_path(@battle)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
    redirect_to campaign_table_path(@campaign), alert: e.message, status: :see_other
  end

  def show
    remember_coop_view(@battle.campaign) if @battle.campaign
    @log = @battle.battle_events.last(40)
    return unless @battle.campaign

    # The table's log and dialogue come along, as this seat may see them.
    @seat = LocalCoop::WATCHED.include?(coop_view(@battle.campaign)) ? Seat.nobody : current_seat # a watched screen sees what everyone sees
    @messages = Message.visible_to(@battle.campaign, @seat).last(Campaigns::TablesController::LOG_LENGTH)
  end
end
