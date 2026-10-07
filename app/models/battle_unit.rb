# frozen_string_literal: true

# One unit in a battle's state, as the app reads it: the pages, the seats,
# the settlement. The resolver keeps working on the plain hash (lib/battle,
# §5); this only reads it, and hands it back (#to_h) wherever the engine
# is asked something (Battle::State.usable?, Battle::Types.effectiveness).
class BattleUnit
  def initialize(data)
    @data = data
  end

  # The engine's own hash, for the engine.
  def to_h = @data

  def id = @data["id"]
  def name = @data["name"]
  def side = @data["side"]
  def party? = side == "party"
  def enemy? = side == "enemy"

  # Fighting beside the party at the GM's call (the "add_unit" override): no seat, no rewards.
  def guest? = @data["guest"] == true
  # Off the field for good: fled, sent off, a summon gone home.
  def gone? = @data["gone"] == true
  def on_field? = !gone?

  def stats = @data["stats"]
  def hp = @data["hp"]
  def mp = @data["mp"]
  def max_hp = stats["max_hp"]
  def max_mp = stats["max_mp"]

  def ko? = hp.zero?
  def standing? = hp.positive?
  def hurt? = standing? && hp < max_hp

  def hp_percent = self.class.hp_percent(hp, max_hp)
  def hp_band = self.class.hp_band(hp, max_hp)

  def self.hp_percent(hp, max_hp) = (100.0 * hp / max_hp).round

  # How worried an HP bar looks: ko, danger, warn or ok. A character's
  # vitals at the table use the same bands as the battle's.
  def self.hp_band(hp, max_hp)
    pct = hp_percent(hp, max_hp)
    if pct.zero? then "ko"
    elsif pct <= 25 then "danger"
    elsif pct <= 50 then "warn"
    else "ok"
    end
  end

  # What lasts on it: [{ "kind", "turns", ... }] and [{ "stat", "amount", "turns" }].
  def statuses = @data["statuses"]
  def buffs = @data["buffs"]
  def status_kinds = statuses.map { |status| status["kind"] }
  def status(kind) = statuses.find { |status| status["kind"] == kind }

  # Its commands' ids, and what it did last (the default when its clock runs out).
  def abilities = @data["abilities"]
  def last_command = @data["last_command"]
  def signature = @data["signature"]
  def attack_type = @data["attack_type"]

  # What it is, for the chart: its types, its own affinities, the statuses it shrugs off.
  def types = @data.fetch("types", [])
  def affinities = @data.fetch("affinities", {})
  def status_immune = @data.fetch("status_immune", [])

  # Where its picture comes from: { "book" => "monsters", "slug" => "goblin" }.
  def image = @data["image"] || {}
  def image_slug = image["slug"]

  # The campaign record behind it, if any: a character's id, or an antagonist's.
  def character_id = Character.from_battle_unit(id)
  def npc_id = Npc.from_battle_unit(id)

  def ==(other) = other.is_a?(BattleUnit) && other.to_h == to_h
  alias eql? ==
  def hash = @data.hash
end
