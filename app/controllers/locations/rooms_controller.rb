# frozen_string_literal: true

# A room of a dungeon, for the GM: added off one it already has, dragged
# to a new place on the floorplan, or opened in the panel beside it.
class Locations::RoomsController < ApplicationController
  include LocationScoped

  before_action :require_table_gm

  # The panel beside the floorplan (locations/_room_panel), in its frame.
  def show
    @room = @location.room(params[:id]) or return back(alert: "That room isn't here any more.")

    render partial: "locations/room_panel", locals: { location: @location, room: @room }
  end

  # Dragged on the floorplan: { room: { x, y } }, answered without a body
  # because the page refreshes itself (MapEdgesController#update does the same).
  def update
    @location.move_room!(params[:id], **params.expect(room: %i[x y]).to_h.symbolize_keys)
    request.format.json? ? head(:no_content) : back("Room moved.")
  end

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
