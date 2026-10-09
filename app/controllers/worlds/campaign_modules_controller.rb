# frozen_string_literal: true

# A campaign module, uploaded into a world (CampaignModule::Import): a new
# campaign from it, with whoever uploaded it as its GM. Anyone who can run
# a game can; a module that needs book entries the world lacks needs
# someone who can change the world's books.
class Worlds::CampaignModulesController < ApplicationController
  include WorldScoped
  before_action :require_account

  def new; end

  def create
    upload = params[:module_file]
    raise Refusal, "Choose a module file (.zip) to import." unless upload.respond_to?(:read)

    campaign = CampaignModule::Import.new(upload, world: @world, gm: current_user, can_add_books: can_edit_world?, name: params[:name]).run!
    redirect_to campaign_prep_path(campaign), notice: "#{campaign.name} begins, from its module.", status: :see_other
  rescue Refusal => e
    redirect_to new_world_campaign_module_path(@world), alert: e.message, status: :see_other
  end
end
