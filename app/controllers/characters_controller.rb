# frozen_string_literal: true

class CharactersController < ApplicationController
  include CampaignScoped
  include PortraitUploads

  before_action :set_campaign, only: %i[new create]
  before_action :set_character, only: %i[show edit update destroy]
  before_action :require_character_manager, only: %i[edit update destroy]

  def new
    @character = @campaign.characters.new(starting_level: 5, starting_job_level: 1,
                                          job: @world.jobs.order(:name).first)
  end

  def create
    # A player's new character is theirs and starts at the party's lowest
    # level. The GM's are unclaimed, for players to sit as, at any level.
    fields = can_gm?(@campaign) ? %i[name player_name job_id starting_level starting_job_level] : %i[name player_name job_id]
    @character = @campaign.characters.new(params.expect(character: fields).merge(user: (current_user unless can_gm?(@campaign))))
    unless can_gm?(@campaign)
      @character.starting_level ||= @campaign.characters.minimum(:level)
      @character.starting_job_level = 1 # the job's first ability, like the GM's default
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
    if @character.update(params.expect(character: can_gm?(@campaign) ? %i[name player_name user_id] : %i[name player_name]))
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
