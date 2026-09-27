# frozen_string_literal: true

# The GM calls for a check at the table (Campaign#check!).
class ChecksController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign

  def create
    return forbid("Only the GM calls for checks.") unless table_seat == "gm"

    fields = params.expect(check: [ :stat, :difficulty, :reason, { characters: [] } ])
    characters = @campaign.characters.where(id: Array(fields[:characters]).compact_blank).order(:created_at).to_a
    @campaign.check!(characters: characters, stat: fields[:stat], difficulty: fields[:difficulty], reason: fields[:reason])
    redirect_back_or_to campaign_table_path(@campaign), status: :see_other
  rescue ArgumentError => e
    redirect_back_or_to campaign_table_path(@campaign), alert: e.message, status: :see_other
  end
end
