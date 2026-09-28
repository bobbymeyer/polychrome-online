# frozen_string_literal: true

# A campaign's legends: the world's history as far as the party knows it,
# and their own story since. The GM sees the rest of the history, and what
# really happened.
class LegendsController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign

  def show
    @gm = table_gm?
    @legends = Legends.new(@campaign, gm: @gm)
  end
end
