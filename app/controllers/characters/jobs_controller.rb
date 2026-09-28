# frozen_string_literal: true

# Changing a character's current job.
class Characters::JobsController < ApplicationController
  include CampaignScoped

  before_action :set_character
  before_action :require_character_manager

  def update
    job = @world.jobs.find(params.expect(:job_id))
    @character.change_job!(job)
    redirect_to character_path(@character), notice: "#{@character.name} is now a #{job.name}.", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    sheet_error(e.record.errors.full_messages.to_sentence)
  end
end
