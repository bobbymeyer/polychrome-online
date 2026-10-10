# frozen_string_literal: true

# The GM's overrides, from what the GM's panel posts to what the resolver
# takes (§5: an override is an action, logged like any other). The panel's
# quick choices become engine terms here: a ruling's strength becomes
# effects, a skill becomes its stat and the character's bonus, a Bestiary
# entry joining the fight becomes a unit.
module BattleRecord::Overrides
  extend ActiveSupport::Concern

  # A ruling's "what success does", from the GM's quick choices to engine effects: physical, typed and healing power.
  RULING_STRENGTH = { "light" => [ 100, 15, 15 ], "medium" => [ 150, 25, 30 ], "heavy" => [ 220, 40, 50 ] }.freeze

  # The override action for the GM's choices (string keys, blanks left out).
  # Raises Battle::InvalidAction for a skill or monster the world hasn't got.
  def gm_override(choices)
    gm = choices.dup
    gm["value"] = gm["value"].to_i if gm["value"]
    gm["turns"] = gm["turns"].to_i if gm["turns"]
    gm["stage"] = gm["stage"].to_i if gm["stage"]
    joining!(gm) if gm["op"] == "add_unit"
    ruling!(gm) if gm["op"] == "rule"
    { "type" => "gm_override", "actor" => "gm" }.merge(gm)
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

    skill = world.skill(gm["stat"].delete_prefix("skill:")) or raise Battle::InvalidAction, "That skill isn't in #{world.name}"
    character = campaign&.characters&.find_by(id: Character.from_battle_unit(gm["unit"]))
    gm.merge!("stat" => skill["stat"], "skill" => skill["name"], "bonus" => character ? character.skill_bonus(skill["slug"]) : 0)
  end

  # A unit joining mid-fight comes from the Bestiary: reinforcements as
  # they are, or a guest fighting beside the party (under a name of the
  # GM's choosing, say an NPC's), who earns nothing and drops nothing.
  def joining!(gm)
    monster = world.monsters.find_by(slug: gm.delete("monster")) or raise Battle::InvalidAction, "Pick a monster from the Bestiary"
    spec = monster.to_engine.except("count")
    if (name = gm.delete("name").presence)
      spec.merge!("name" => name, "id" => name.parameterize(separator: "_").presence || spec["id"])
    end
    spec.merge!("rewards" => {}, "drops" => []) if gm["side"] == "party"
    gm["unit"] = spec
    gm["abilities"] = world.ability_library.slice(*(spec["abilities"] + spec["ai"].map { |rule| rule["use"] }))
  end
end
