# frozen_string_literal: true

# Submits one action to the resolver. Players can only command their own
# unit; only the GM seat can send overrides (which the resolver logs, §12).
class BattleActionsController < ApplicationController
  include BattleSeat

  GM_FIELDS = %i[op unit value status turns result note monster side name].freeze

  before_action :set_battle

  def create
    action, actor = build_action
    return head :forbidden unless action

    @battle.apply!(action, actor: actor)
    @battle.set_auto!(actor, false) if @battle.auto?(actor) # someone is here to play them now
    # The panel must not show the new state before the beat has played
    # (§6), so the response is a placeholder. The battle player reloads the
    # real panel once the animation finishes.
    render "panels/resolving", layout: false
  rescue Battle::InvalidAction => e
    @error = e.message
    render "panels/show", layout: false, status: :unprocessable_content
  end

  private

  # A unit joining mid-fight comes from the Bestiary: reinforcements as
  # they are, or a guest fighting beside the party (under a name of the
  # GM's choosing, say an NPC's), who earns nothing and drops nothing.
  def joining!(gm)
    monster = @battle.world.monsters.find_by(slug: gm.delete("monster")) or raise Battle::InvalidAction, "Pick a monster from the Bestiary"
    spec = monster.to_engine.except("count")
    if (name = gm.delete("name").presence)
      spec.merge!("name" => name, "id" => name.parameterize(separator: "_").presence || spec["id"])
    end
    spec.merge!("rewards" => {}, "drops" => []) if gm["side"] == "party"
    gm["unit"] = spec
    gm["abilities"] = @battle.world.ability_library.slice(*(spec["abilities"] + spec["ai"].map { |rule| rule["use"] }))
  end

  def build_action
    if params[:gm] && gm_seat?
      gm = params.expect(gm: GM_FIELDS).to_h.compact_blank
      gm["value"] = gm["value"].to_i if gm["value"]
      gm["turns"] = gm["turns"].to_i if gm["turns"]
      joining!(gm) if gm["op"] == "add_unit"
      [ { "type" => "gm_override", "actor" => "gm" }.merge(gm), "gm" ]
    elsif params[:command] && seat_unit
      command = params.expect(command: %i[kind ability item target timing]).to_h.compact_blank
      [ { "type" => "command", "actor" => seat_unit["id"], "command" => command }, seat_unit["id"] ]
    end
  end
end
