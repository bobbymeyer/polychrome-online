# frozen_string_literal: true

# The way in from an invite: the link or code the GM shares (the campaign
# page's "Invite players"), or the QR code on a local co-op shared screen.
# Pick a character nobody plays yet, or make your own, and sit down. No
# account needed: someone who isn't signed in joins with just a name
# (User.guest!).
#
# From the shared screen's QR code (?view=controller), this device becomes
# a controller; from an invite, it opens the table.
class JoinsController < ApplicationController
  include TableSeat

  allow_unauthenticated_access
  before_action :resume_session
  before_action :set_campaign
  rate_limit to: 20, within: 3.minutes, only: :create, with: -> { redirect_to join_path(params[:code]), alert: "Too many tries. Wait a moment." }

  def show
    @characters = open_characters
    @character = @campaign.characters.new(job: @campaign.available_jobs.first)
  end

  def create
    character = params[:character] ? new_character : @campaign.characters.find(params.expect(:character_id))
    return render_new_character(character) unless character.persisted?
    return redirect_to(join_path(@campaign.join_code, view: controller_view), alert: "#{character.name} is someone else's.") unless claim_table_seat(@campaign, character.id)

    redirect_to campaign_table_path(@campaign, view: controller_view || "off"), status: :see_other
  end

  private

  def set_campaign
    @campaign = Campaign.find_by(join_code: params[:code].to_s.upcase) or
      redirect_to(root_path, alert: "That invite isn't in use any more. Ask the GM for the new one.")
    @world = @campaign&.world
  end

  # Characters you could sit as: nobody's yet, or already yours.
  def open_characters
    @campaign.characters.includes(:job).order(:created_at).select { |c| c.user_id.nil? || c.user_id == current_user&.id }
  end

  def controller_view
    "controller" if params[:view] == "controller"
  end

  # A character of your own, at the party's lowest level. It's yours as
  # soon as it's made, so nobody else can sit in it.
  def new_character
    character = @campaign.newcomer(params.expect(character: %i[name job_id motive]))
    return character unless character.valid?

    sign_in_as_guest(character.name)
    character.user = current_user
    character.save!
    character
  end

  def render_new_character(character)
    @character = character
    @characters = open_characters
    render :show, status: :unprocessable_content
  end

  def sign_in_as_guest(fallback)
    return if current_user

    name = params[:name].to_s.strip.presence || fallback
    start_new_session_for(User.guest!(name.first(60)))
  end

  def claim_table_seat(campaign, character_id)
    sign_in_as_guest(campaign.characters.find(character_id).name)
    super
  end
end
