# frozen_string_literal: true

# The mode a place is in: set off at the table, or ended.
class MapNodes::CurrentModesController < ApplicationController
  include PlaceScoped

  def update
    @node.switch_mode!(params.expect(:key))
    back "#{@node.name}: #{@node.current_mode['name']}."
  end

  def destroy
    @node.clear_mode!(params[:line])
    back "#{@node.name} is itself again."
  end
end
