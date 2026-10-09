# frozen_string_literal: true

# Submits one action to the resolver. Players can only command their own
# unit; only the GM seat can send overrides (which the resolver logs, §12).
class Battles::ActionsController < ApplicationController
  include BattleSeat

  GM_FIELDS = %i[op unit value status turns result note monster side name stat difficulty aim effect strength type success failure].freeze

  # A ruling's "what success does", from the GM's quick choices to engine effects.
  RULING_STRENGTH = { "light" => [ 100, 15, 15 ], "medium" => [ 150, 25, 30 ], "heavy" => [ 220, 40, 50 ] }.freeze

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

  # The GM's ruling on an idea, from quick choices: damage (typed or not),
  # a status, healing, or just the story.
  def ruling!(gm)
    skilled!(gm)
    physical, magic, heal = RULING_STRENGTH.fetch(gm.delete("strength") || "medium", RULING_STRENGTH["medium"])
    type = gm.delete("type").presence
    status = gm.delete("status").presence
    gm["effects"] = case gm.delete("effect")
    when "damage" then [ type ? { "primitive" => "elemental", "type" => type, "power" => magic } : { "primitive" => "physical", "power" => physical } ]
    when "status" then status ? [ { "primitive" => "status", "kind" => status, "chance" => 100, "duration" => 3 } ] : []
    when "heal" then [ { "primitive" => "heal", "power" => heal } ]
    else []
    end
  end

  # "skill:<slug>": the world's skill, rolled on its stat, with the job
  # bonus of the character trying it.
  def skilled!(gm)
    return unless gm["stat"].to_s.start_with?("skill:")

    skill = @battle.world.skill(gm["stat"].delete_prefix("skill:")) or raise Battle::InvalidAction, "That skill isn't in #{@battle.world.name}"
    character = @battle.campaign&.characters&.find_by(id: Character.from_battle_unit(gm["unit"]))
    gm.merge!("stat" => skill["stat"], "skill" => skill["name"], "bonus" => character ? character.skill_bonus(skill["slug"]) : 0)
  end

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
      ruling!(gm) if gm["op"] == "rule"
      [ { "type" => "gm_override", "actor" => "gm" }.merge(gm), "gm" ]
    elsif params[:command] && seat_unit
      command = params.expect(command: %i[kind ability item target timing text stance technique]).to_h.compact_blank
      [ { "type" => "command", "actor" => seat_unit["id"], "command" => command }, seat_unit["id"] ]
    end
  end
end
