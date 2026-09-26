# frozen_string_literal: true

class BattlesController < ApplicationController
  include BattleSeat

  PARTY_SLOTS = 4
  ENCOUNTER_SLOTS = 3

  before_action :set_world, only: %i[index new create]
  before_action :set_battle, only: :show

  def index
    @battles = @world.battles.order(updated_at: :desc)
  end

  def new
    @setup = default_setup
  end

  def create
    @setup = setup_params
    party = QuickParty.new(@world).build(@setup[:party].select { |m| m[:job].present? })
    encounter = @setup[:encounter].select { |row| row[:monster].present? }
                                  .to_h { |row| [ row[:monster], row[:count].to_i.clamp(1, 8) ] }
    if party.empty? || encounter.empty?
      @error = "A battle needs at least one party member and one monster."
      return render :new, status: :unprocessable_content
    end

    @battle = BattleRecord.start!(
      world: @world, name: @setup[:name].presence || "Battle", party: party, encounter: encounter,
      seed: @setup[:seed], escapable: @setup[:escapable] != "0", input_seconds: @setup[:input_seconds].presence&.to_i
    )
    take_seat("gm")
    redirect_to battle_path(@battle)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
    @error = e.message
    render :new, status: :unprocessable_content
  end

  def show
    @log = @battle.battle_events.last(40)
  end

  private

  def set_world
    @world = World.find_by!(slug: params[:world_slug])
  end

  def default_setup
    jobs = @world.jobs.where.not(slug: "freelancer").order(:name).limit(PARTY_SLOTS).pluck(:slug)
    monster = @world.monsters.order(:level).first&.slug
    {
      name: "Battle", seed: nil, escapable: "1", input_seconds: "60",
      party: Array.new(PARTY_SLOTS) { |i| { name: "", job: jobs[i].to_s } },
      encounter: [ { monster: monster.to_s, count: "3" } ] + Array.new(ENCOUNTER_SLOTS - 1) { { monster: "", count: "1" } }
    }
  end

  def setup_params
    raw = params.expect(battle: [ :name, :seed, :escapable, :input_seconds,
                                  { party: [ %i[name job] ], encounter: [ %i[monster count] ] } ])
    rows = ->(value) { JsonCasting.rows(value).map(&:symbolize_keys) }
    raw.to_h.symbolize_keys.merge(party: rows.(raw[:party]), encounter: rows.(raw[:encounter]))
  end
end
