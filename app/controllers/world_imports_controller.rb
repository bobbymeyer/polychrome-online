# frozen_string_literal: true

# A world package, uploaded (WorldPackage::Import): a new world from it,
# owned by whoever uploaded it, as "Copy this world" makes one.
class WorldImportsController < ApplicationController
  before_action :require_account

  def new; end

  def create
    upload = params[:package_file]
    raise Refusal, "Choose a world file (.zip) to import." unless upload.respond_to?(:read)

    world = WorldPackage::Import.new(upload, owner: current_user, name: params[:name], slug: params[:slug]).run!
    redirect_to world_path(world), notice: "#{world.name} was imported. It's yours to change.", status: :see_other
  rescue Refusal => e
    redirect_to new_world_import_path, alert: e.message, status: :see_other
  end
end
