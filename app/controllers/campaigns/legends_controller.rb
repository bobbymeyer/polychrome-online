# frozen_string_literal: true

# A campaign's legends: the world's history as far as the party knows it,
# and their own story since. The GM sees the rest of the history, and what
# really happened.
class Campaigns::LegendsController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign

  def show
    @gm = table_gm?
    @legends = Legends.new(@campaign, gm: @gm)
    @battles = @campaign.battles.order(created_at: :desc).limit(20)
  end
end
