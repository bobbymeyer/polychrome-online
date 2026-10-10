# frozen_string_literal: true

# The whole world, downloaded as a package (WorldPackage::Export): to take
# to another server, or hand to another author. It carries the GM's side
# (codex notes, places' notes, fronts' secrets), so it's for those who know
# the lore: the world's editors and the GMs playing in it.
class Worlds::PackagesController < ApplicationController
  include WorldScoped
  before_action :require_lore

  def show
    export = WorldPackage::Export.new(@world)
    send_data export.to_zip, type: "application/zip", filename: export.filename
  end
end
