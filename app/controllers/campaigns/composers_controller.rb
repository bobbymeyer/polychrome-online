# frozen_string_literal: true

# The message composer, served into a Turbo Frame so it keeps the GM's
# chosen speaker and expression between lines.
class Campaigns::ComposersController < Campaigns::BaseController
  def show
    @message = @campaign.messages.new(expression: "neutral")
    render layout: false
  end
end
