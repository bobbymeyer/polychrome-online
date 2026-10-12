# frozen_string_literal: true

# The campaign's art and music needs, downloaded as a baible skeleton
# (BaibleSkeleton): a JSON file for baible to import. The GM's.
class Campaigns::BaibleSkeletonsController < Campaigns::BaseController
  before_action :require_campaign_gm

  def show
    skeleton = BaibleSkeleton.new(@campaign)
    send_data skeleton.to_json, type: "application/json", filename: skeleton.filename
  end
end
