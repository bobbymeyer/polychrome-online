# frozen_string_literal: true

# Something a unit can use in a battle: one of its abilities, or one of the
# party's items. Both are the books' entries as the battle copied them in
# when it started (lib/battle, §9.8), read here for the pages. Like
# BattleUnit, it only reads the resolver's plain hash and hands it back
# (#to_h) wherever the engine is asked something.
class BattleMove
  def initialize(data, item: false)
    @data = data
    @item = item
  end

  # The engine's own hash, for the engine.
  def to_h = @data

  def item? = @item
  def ability? = !@item

  def id = @data["id"]
  def name = @data["name"]
  # An ability's kind: "skill", "magic", ... (Battle::ABILITY_KINDS). Magic is what silence stops.
  def kind = @data["kind"]
  def magic? = kind == "magic"
  # Who it reaches: single_enemy, all_allies, self, ... (Battle::TARGETINGS).
  def target = @data["target"]
  def effects = @data.fetch("effects", [])
  def gesture = @data["gesture"]
  # How many of an item the party carried in (BattleState#items_left says how many are still free).
  def count = @data["count"]

  def mp_cost = Battle::State.ability_cost(@data)

  def ==(other) = other.is_a?(BattleMove) && other.to_h == to_h && other.item? == item?
  alias eql? ==
  def hash = [ @data, @item ].hash
end
