# frozen_string_literal: true

# The GM calls for a check at the table (Campaign#check!).
class Campaigns::ChecksController < Campaigns::BaseController
  before_action :require_table_gm

  def create
    fields = params.expect(check: [ :stat, :difficulty, :reason, :outcome, :amount, :failure, { characters: [] } ])
    characters = @campaign.characters.where(id: Array(fields[:characters]).compact_blank).order(:created_at).to_a
    outcome = Outcome.of(fields[:outcome], fields[:amount].presence&.to_i) if Outcome::ON_A_CHECK.include?(fields[:outcome])
    outcome&.can_happen!(@campaign)
    failure = Outcome.of(fields[:failure]) if Outcome::ON_A_FAILURE.include?(fields[:failure])
    @campaign.check!(characters: characters, stat: fields[:stat], difficulty: fields[:difficulty], reason: fields[:reason], outcome: outcome, failure: failure)
    redirect_back_or_to campaign_table_path(@campaign), status: :see_other
  end
end
