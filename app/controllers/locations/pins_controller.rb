# frozen_string_literal: true

# Pinning a service, room or townsperson so rerolls keep them; a pinned
# townsperson becomes a real NPC (Location#pin!).
class Locations::PinsController < ApplicationController
  include LocationScoped

  before_action :require_gm

  def create
    @location.pin!(params.expect(:key))
    back "Pinned."
  end

  def destroy
    @location.unpin!(params.expect(:id))
    back "Unpinned."
  end
end
