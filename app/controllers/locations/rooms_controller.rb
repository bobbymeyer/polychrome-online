# frozen_string_literal: true

# A room the GM adds to a dungeon, off one it already has.
class Locations::RoomsController < ApplicationController
  include LocationScoped

  before_action :require_gm

  def create
    room = params.expect(room: %i[name connect kind text item gil monster count])
    @location.add_room!(name: room[:name].presence || "Hidden Room", connect: room[:connect], decision: decision_from(room))
    back "Room added."
  end

  private

  def decision_from(room)
    case room[:kind]
    when "encounter" then { "kind" => "encounter", "monsters" => { room[:monster] => room[:count].to_i.clamp(1, 8) } }
    when "treasure"
      room[:gil].to_i.positive? ? { "kind" => "treasure", "gil" => room[:gil].to_i } : { "kind" => "treasure", "item" => room[:item] }
    else { "kind" => "event", "text" => room[:text].presence || "Something waits here." }
    end
  end
end
