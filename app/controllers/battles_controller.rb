# frozen_string_literal: true

class BattlesController < ApplicationController
  include BattleSeat
  include CampaignScoped

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
    @setup = setup_params
    characters = @campaign.characters.where(id: @setup[:characters]).order(:created_at).to_a
    encounter = @setup[:encounter].select { |row| row[:monster].present? }
                                  .to_h { |row| [ row[:monster], row[:count].to_i.clamp(1, 8) ] }
    antagonists = @campaign.npcs.at_large.where(id: @setup[:antagonists]).to_a
    @error = if characters.none?(&:conscious?) then "Pick at least one character who is still standing."
    elsif encounter.empty? && antagonists.empty? then "Pick at least one monster or antagonist."
    end
    return redirect_to(campaign_table_path(@campaign), alert: @error, status: :see_other) if @error

    @battle = BattleRecord.start!(
      campaign: @campaign, characters: characters, name: @setup[:name].presence || "Battle", encounter: encounter,
      seed: @setup[:seed], escapable: @setup[:escapable] != "0", input_seconds: @setup[:input_seconds].presence&.to_i,
      terrain: @setup[:terrain].presence_in(@campaign.world.type_chart.slugs), antagonists: antagonists
    )
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

  private

  def setup_params
    raw = params.expect(battle: [ :name, :seed, :escapable, :input_seconds, :terrain, { characters: [], antagonists: [], encounter: [ %i[monster count] ] } ])
    raw.to_h.symbolize_keys.merge(
      characters: Array(raw[:characters]).compact_blank.map(&:to_i),
      antagonists: Array(raw[:antagonists]).compact_blank.map(&:to_i),
      encounter: JsonCasting.rows(raw[:encounter]).map(&:symbolize_keys).first(BattleSetup::ENCOUNTER_SLOTS)
    )
  end
end
