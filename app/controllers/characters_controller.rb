# frozen_string_literal: true

class CharactersController < ApplicationController
  include CampaignScoped
  include PortraitUploads

  before_action :set_campaign, only: %i[new create]
  before_action :set_character, only: %i[show edit update destroy]
  before_action :require_character_manager, only: %i[edit update destroy]

  def new
    @character = @campaign.characters.new(starting_level: Campaign::FIRST_LEVEL,
                                          job: @campaign.available_jobs.first)
  end

  # Where they're from, their home on the map, who they're tied to.
  ORIGIN_FIELDS = [ :origin, :home_node_id, { ties: [ %i[npc_id text] ] } ].freeze

  def create
    # A player's new character is theirs (Campaign#newcomer). The GM's are
    # unclaimed, for players to sit as, at any level.
    if can_gm?(@campaign)
      @character = @campaign.characters.new(params.expect(character: [ :name, :motive, :player_name, :job_id, :starting_level, :starting_job_level, *ORIGIN_FIELDS ]))
    else
      @character = @campaign.newcomer(params.expect(character: [ :name, :motive, :job_id, *ORIGIN_FIELDS ]), user: current_user)
    end
    if @character.save
      redirect_to character_path(@character), notice: "#{@character.name} joins the party."
    else
      render :new, status: :unprocessable_content
    end
  end

  def show; end

  def edit; end

  def update
    fields = can_gm?(@campaign) ? %i[name motive player_name user_id colour] : %i[name motive player_name colour]
    if @character.update(params.expect(character: [ *fields, *ORIGIN_FIELDS ]))
      @character.update_portraits!(**portrait_params)
      redirect_to character_path(@character), notice: "#{@character.name} was updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @character.equipment_slots.each { |slot| @character.unequip!(slot.slot) }
    @character.destroy!
    redirect_to campaign_path(@campaign), notice: "#{@character.name} left the party. Their gear went to the bag.",
                                          status: :see_other
  end
end
