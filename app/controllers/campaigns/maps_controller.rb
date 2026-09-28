# frozen_string_literal: true

class Campaigns::MapsController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign

  def show
    @gm = table_gm?
  end
end
