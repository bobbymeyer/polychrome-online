# frozen_string_literal: true

# A player picking an option, as their own character.
class Choices::PicksController < ApplicationController
  include ChoiceScoped

  def create
    seat = table_seat
    return forbid("Sit as your character to pick.") unless seat.character?

    pick = @choice.picks.find_or_initialize_by(character: seat.character)
    pick.option = params[:option]
    pick.save ? head(:no_content) : forbid(pick.errors.full_messages.to_sentence)
  end
end
