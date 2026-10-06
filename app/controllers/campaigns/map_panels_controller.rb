# frozen_string_literal: true

# The GM's map overview: where the party is, the pending encounter, and
# the paths out.
class Campaigns::MapPanelsController < Campaigns::BaseController
  include MapGm

  before_action :require_table_gm

  def show
    render layout: false
  end
end
