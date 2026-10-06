# frozen_string_literal: true

# The GM grants an archetype at the table, to the party or to someone, who
# awakens to it (Campaign#grant_job!): a story reward.
class Campaigns::JobGrantsController < Campaigns::BaseController
  before_action :require_table_gm

  def create
    job = @campaign.world.jobs.find_by!(slug: params.expect(:job))
    to = @campaign.characters.find(params[:character_id]) if params[:character_id].present?
    @campaign.grant_job!(job, to: to, line: params[:line])
    redirect_back_or_to campaign_table_path(@campaign), status: :see_other
  end
end
