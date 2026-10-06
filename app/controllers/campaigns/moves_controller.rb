# frozen_string_literal: true

# The GM's moves panel (Campaign::Moves): what's live, shown in the GM's
# tools when they open it, and a line from it made so. GM seat only.
class Campaigns::MovesController < ApplicationController
  include CampaignScoped
  include TableSeat

  before_action :set_campaign
  before_action :require_table_gm

  def show
    facts = @campaign.moment # read once, for the moves and the dangers
    @moves = @campaign.moves_now(facts: facts)
    @dangers = @campaign.dangers(facts: facts)
    @wants = @campaign.wants_heard
    @got_away = @campaign.got_away
    @chains = @campaign.chains
  end

  # A line from the panel: its words, what its row remembers ("smoke_seen,
  # visits + 1", read again here) and, for a hard move, what it takes.
  def create
    fields = params.expect(move: %i[text sets does])
    writes, problems = Story::Criteria.parse_writes(fields[:sets])
    raise Refusal, problems.first if problems.any?

    @campaign.say_line!(fields[:text], sets: writes.map { |w| w.to_h.transform_keys(&:to_s) }, does: fields[:does].presence)
    redirect_to campaign_moves_path(@campaign), status: :see_other
  rescue Refusal => e
    redirect_to campaign_moves_path(@campaign), alert: e.message, status: :see_other
  end
end
