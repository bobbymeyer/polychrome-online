# frozen_string_literal: true

# Submits one action to the resolver. Players can only command their own
# unit; only the GM seat can send overrides (which the resolver logs, §12).
class Battles::ActionsController < ApplicationController
  include BattleSeat

  GM_FIELDS = %i[op unit value status turns result note monster side name stat difficulty aim effect strength type success failure].freeze

  before_action :set_battle

  def create
    action, actor = build_action
    return head :forbidden unless action

    @battle.apply!(action, actor: actor)
    @battle.set_auto!(actor, false) if @battle.auto?(actor) # someone is here to play them now
    @battle.arrive!(actor) unless actor == "gm" # choosing a move is being ready
    # The panel must not show the new state before the beat has played
    # (§6), so the response is a placeholder. The battle player reloads the
    # real panel once the animation finishes.
    render "battles/panels/resolving", layout: false
  rescue Battle::InvalidAction => e
    @error = e.message
    render "battles/panels/show", layout: false, status: :unprocessable_content
  end

  private

  def build_action
    if params[:gm] && gm_seat?
      [ @battle.gm_override(params.expect(gm: GM_FIELDS).to_h.compact_blank), "gm" ]
    elsif params[:command] && seat_unit
      command = params.expect(command: %i[kind ability item target timing text]).to_h.compact_blank
      [ { "type" => "command", "actor" => seat_unit["id"], "command" => command }, seat_unit["id"] ]
    end
  end
end
