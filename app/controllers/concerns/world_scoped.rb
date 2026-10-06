# frozen_string_literal: true

# A world's books and pages (app/controllers/worlds/, the book controllers):
# the world in the URL is loaded for every action, ahead of the editor and
# lore checks (Authorization) that read it.
module WorldScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_world
  end

  private

  def set_world
    @world = World.find_by!(slug: params[:world_slug])
  end
end
