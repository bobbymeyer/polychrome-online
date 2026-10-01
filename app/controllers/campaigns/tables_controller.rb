# frozen_string_literal: true

# The campaign's table: one long-lived page (§9.9) with the dialogue box, the
# log and a composer for whoever is sitting here.
class Campaigns::TablesController < ApplicationController
  include CampaignScoped
  include TableSeat

  LOG_LENGTH = 80

  before_action :set_campaign

  def show
    remember_coop_view(@campaign)
    # The shared screen is for everyone to see: a spectator's view, whoever is
    # signed in on it, so no GM map, notes or whispers end up on the TV.
    @seat = coop_view(@campaign) == "screen" ? Seat.nobody : table_seat
    @messages = Message.visible_to(@campaign, @seat).last(LOG_LENGTH)
    # The last thing said stays up in the dialogue box, unless the party has
    # moved on since: then it was said somewhere else (Campaign::MOVED).
    last = @messages.reverse.find(&:dialogue?)
    @last_dialogue = last unless last && @messages.any? { |m| m.id > last.id && m.data.to_h["moved"] }
    @recap = Recap.for(@campaign)
    @recap = nil if @recap&.empty?
  end
end
