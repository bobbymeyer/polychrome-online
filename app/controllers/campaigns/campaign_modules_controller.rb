# frozen_string_literal: true

# The campaign's prep, downloaded as a module (CampaignModule::Export): a
# .zip another GM can start a campaign from. The GM's.
class Campaigns::CampaignModulesController < Campaigns::BaseController
  before_action :require_campaign_gm

  def show
    export = CampaignModule::Export.new(@campaign)
    send_data export.to_zip, type: "application/zip", filename: export.filename
  end
end
