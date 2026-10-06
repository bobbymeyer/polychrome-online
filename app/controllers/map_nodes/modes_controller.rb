# frozen_string_literal: true

# A place's other states, prepared by the GM (MapNode::Modes).
class MapNodes::ModesController < ApplicationController
  include PlaceScoped

  def create
    fields = params.expect(mode: [ :name, :line, :description, :music, :encounters, :activities, { closed: [], times: [] } ])
    @node.add_mode!(fields.to_h)
    back "#{fields[:name]} is ready to set off."
  rescue ActiveRecord::RecordInvalid => e
    back alert: e.record.errors.full_messages.to_sentence
  end

  def destroy
    @node.remove_mode!(params.expect(:id))
    back "Mode removed."
  end
end
