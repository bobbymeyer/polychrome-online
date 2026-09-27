# frozen_string_literal: true

class BattlesController < ApplicationController
  include BattleSeat
  include CampaignScoped

  ENCOUNTER_SLOTS = 3

  before_action :set_campaign, only: %i[new create]
  before_action :require_campaign_gm, only: %i[new create]
  before_action :set_battle, only: %i[show call_off]

  def new
    @setup = default_setup
  end

  def create
    @setup = setup_params
    characters = @campaign.characters.where(id: @setup[:characters]).order(:created_at).to_a
    encounter = @setup[:encounter].select { |row| row[:monster].present? }
                                  .to_h { |row| [ row[:monster], row[:count].to_i.clamp(1, 8) ] }
    @error = if characters.none?(&:conscious?) then "Pick at least one character who is still standing."
    elsif encounter.empty? then "Pick at least one monster."
    end
    return render :new, status: :unprocessable_content if @error

    @battle = BattleRecord.start!(
      campaign: @campaign, characters: characters, name: @setup[:name].presence || "Battle", encounter: encounter,
      seed: @setup[:seed], escapable: @setup[:escapable] != "0", input_seconds: @setup[:input_seconds].presence&.to_i
    )
    take_seat("gm")
    redirect_to battle_path(@battle)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
    @error = e.message
    render :new, status: :unprocessable_content
  end

  # For a battle nobody will finish (BattleRecord#call_off!).
  def call_off
    return forbid unless battle_gm?

    @battle.call_off!
    redirect_back_or_to battle_path(@battle), notice: "#{@battle.name} was called off.", status: :see_other
  end

  def show
    @log = @battle.battle_events.last(40)
    return unless @battle.campaign

    # The table's log and dialogue come along, as this seat may see them.
    seat = current_seat
    @chat_seat = seat == "gm" ? "gm" : (seat && seat_character(seat))
    @messages = Message.visible_to(@battle.campaign, @chat_seat).last(TablesController::LOG_LENGTH)
  end

  private

  def default_setup
    monster = @world.monsters.order(:level).first&.slug
    {
      name: "Battle", seed: nil, escapable: "1", input_seconds: BattleRecord::DEFAULT_TIMER.to_s,
      characters: @campaign.characters.select(&:conscious?).first(4).map(&:id),
      encounter: [ { monster: monster.to_s, count: "3" } ] + Array.new(ENCOUNTER_SLOTS - 1) { { monster: "", count: "1" } }
    }
  end

  def setup_params
    raw = params.expect(battle: [ :name, :seed, :escapable, :input_seconds, { characters: [], encounter: [ %i[monster count] ] } ])
    raw.to_h.symbolize_keys.merge(
      characters: Array(raw[:characters]).compact_blank.map(&:to_i),
      encounter: JsonCasting.rows(raw[:encounter]).map(&:symbolize_keys)
    )
  end
end
