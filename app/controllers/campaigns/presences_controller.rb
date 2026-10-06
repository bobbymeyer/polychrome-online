# frozen_string_literal: true

# A seated player has the table open (heartbeat_controller, now and then):
# the party panel says they're here (Character#seen!).
class Campaigns::PresencesController < Campaigns::BaseController
  def update
    table_seat(@campaign).character&.seen!
    head :no_content
  end
end
