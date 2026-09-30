# frozen_string_literal: true

# The shop's stock, set by the GM, or back to what was rolled.
class Locations::StocksController < ApplicationController
  include LocationScoped

  before_action :require_table_gm

  def update
    @location.set_stock!(Array(params.dig(:stock, :items)))
    back "Stock updated."
  end

  def destroy
    @location.set_stock!(nil)
    back "Stock is back to what was rolled."
  end
end
