# frozen_string_literal: true

# Joining local co-op from the shared screen's QR code (LocalCoop): pick
# your character, and this device becomes your controller. No account
# needed: someone who isn't signed in joins with just a name (User.guest!).
class JoinsController < ApplicationController
  include TableSeat

  allow_unauthenticated_access
  before_action :resume_session
  before_action :set_campaign
  rate_limit to: 20, within: 3.minutes, only: :create, with: -> { redirect_to join_path(params[:code]), alert: "Too many tries. Wait a moment." }

  def show
    @characters = @campaign.characters.includes(:job).order(:created_at).select { |c| c.user_id.nil? || c.user_id == current_user&.id }
  end

  def create
    character = @campaign.characters.find(params.expect(:character_id))
    unless current_user
      name = params[:name].to_s.strip.presence || character.name
      start_new_session_for(User.guest!(name.first(60)))
    end
    return redirect_to(join_path(@campaign.join_code), alert: "#{character.name} is someone else's.") unless claim_table_seat(@campaign, character.id)

    redirect_to campaign_table_path(@campaign, view: "controller"), status: :see_other
  end

  private

  def set_campaign
    @campaign = Campaign.find_by(join_code: params[:code].to_s.upcase) or
      redirect_to(root_path, alert: "That join code isn't in use. Scan the screen again.")
    @world = @campaign&.world
  end
end
