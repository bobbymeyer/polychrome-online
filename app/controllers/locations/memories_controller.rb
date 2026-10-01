# frozen_string_literal: true

# A visited place remembers the tables it was rolled from, so its people
# keep their names when the world's tables change (Location::Generation
# #remember!). Letting go takes the world's tables again, same seed.
class Locations::MemoriesController < ApplicationController
  include LocationScoped

  before_action :require_table_gm

  def destroy
    @location.forget_tables!
    back "Rolled from the world's tables as they are now."
  end
end
