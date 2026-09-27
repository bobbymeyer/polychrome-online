# frozen_string_literal: true

# A town or dungeon page. Players may look once its map place is revealed;
# everything else is the GM's (§7: reroll, pin, add hand-authored NPC/room,
# place boss, override stock), plus moving the party through a dungeon.
class LocationsController < ApplicationController
  include TableSeat

  before_action :set_location
  before_action :require_gm, except: :show

  rescue_from ArgumentError do |error|
    redirect_to location_path(@location), alert: error.message, status: :see_other
  end

  def show
    @gm = table_gm?
    head :not_found unless @gm || @location.map_node&.visible?
  end

  def update
    @location.rename!(params.expect(location: [ :name ])[:name])
    back "Renamed."
  end

  def reroll
    @location.reroll!
    back "Rerolled. Pinned things stayed put."
  end

  def pin
    @location.pin!(params.expect(:key))
    back "Pinned."
  end

  def unpin
    @location.unpin!(params.expect(:key))
    back "Unpinned."
  end

  def stock
    @location.set_stock!(params[:reset] ? nil : Array(params.dig(:stock, :items)))
    back params[:reset] ? "Stock is back to what was rolled." : "Stock updated."
  end

  def boss
    boss = params.expect(boss: %i[monster count])
    @location.place_boss!(boss[:monster].present? ? { boss[:monster] => boss[:count] } : {})
    back boss[:monster].present? ? "Boss placed." : "The boss is back to what was rolled."
  end

  def add_npc
    fields = params.expect(npc: %i[name title description])
    @campaign.npcs.create!(fields.merge(location: @location))
    @location.touch
    back "#{fields[:name]} added to #{@location.name}."
  rescue ActiveRecord::RecordInvalid => e
    back alert: e.record.errors.full_messages.to_sentence
  end

  def add_room
    room = params.expect(room: %i[name connect kind text item gil monster count])
    @location.add_room!(name: room[:name].presence || "Hidden Room", connect: room[:connect], decision: decision_from(room))
    back "Room added."
  end

  def enter
    @location.enter!
    back "The party enters #{@location.name}."
  end

  def move
    @location.move_to!(params.expect(:room))
    back
  end

  # Undo one GM change (from the campaign's changes page or here).
  def revert
    @location.revert!(params.expect(:kind), params[:key].presence)
    back_to = url_from(params[:return_to])
    back_to ? redirect_to(back_to, notice: "Reverted.", status: :see_other) : back("Reverted.")
  end

  # Turns: the place's other states (Location#turn_to!).
  def add_turn
    fields = params.expect(turn: [ :name, :line, :description, :music, :encounters, { closed: [] } ])
    @location.add_turn!(fields.to_h)
    back "#{fields[:name]} is ready to set off."
  rescue ActiveRecord::RecordInvalid => e
    back alert: e.record.errors.full_messages.to_sentence
  end

  def turn
    @location.turn_to!(params.expect(:key))
    back "#{@location.name}: #{@location.current_turn['name']}."
  end

  def settle_turn
    @location.settle_turn!(params[:line])
    back "#{@location.name} is itself again."
  end

  def remove_turn
    @location.remove_turn!(params.expect(:key))
    back "Turn removed."
  end

  def take_treasure
    @location.take_treasure!(params.expect(:room))
    back "Added to the party bag."
  end

  private

  def set_location
    @location = Location.find(params[:id])
    @campaign = @location.campaign
    @world = @campaign.world
  end

  def require_gm
    head :forbidden unless table_gm?
  end

  def back(notice = nil, alert: nil)
    redirect_to location_path(@location), notice: notice, alert: alert, status: :see_other
  end

  def decision_from(room)
    case room[:kind]
    when "encounter" then { "kind" => "encounter", "monsters" => { room[:monster] => room[:count].to_i.clamp(1, 8) } }
    when "treasure"
      room[:gil].to_i.positive? ? { "kind" => "treasure", "gil" => room[:gil].to_i } : { "kind" => "treasure", "item" => room[:item] }
    else { "kind" => "event", "text" => room[:text].presence || "Something waits here." }
    end
  end
end
