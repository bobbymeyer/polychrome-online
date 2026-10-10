# frozen_string_literal: true

# The ways between a dungeon's rooms, for the GM: joined from a room's
# panel, cut from either end. A way is the party's road through the place
# (Location::Exploration#neighbours), so this is what the dungeon's shape
# is made of -- not decoration. The generator's data calls these paths;
# every screen calls them ways.
class Locations::WaysController < ApplicationController
  include LocationScoped

  before_action :require_table_gm

  def create
    joined = params.expect(path: %i[from to])
    @location.connect_rooms!(joined[:from], joined[:to])
    back "Joined."
  end

  def destroy
    @location.cut_path!(params[:id])
    back "Cut."
  end
end
