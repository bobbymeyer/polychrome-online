# frozen_string_literal: true

# A battle's state as the app reads it: its units (BattleUnit), the round's
# commands so far, and the engine's questions about them asked in one
# place. Read-only, over the resolver's plain hash (lib/battle, §5), which
# stays the truth: a page can be drawn from any state (a beat's `before`
# as well as the battle's own) by wrapping it.
#
#   field = BattleState.new(battle.state)
#   field.on_field("enemy").each { |unit| unit.name }
class BattleState
  def initialize(data)
    @data = data
  end

  # The engine's own hash, for the engine.
  def to_h = @data

  def status = @data["status"]
  def round = @data["round"]
  def escapable? = @data["escapable"] == true
  def terrain = @data["terrain"]
  # The battle's copy of its world's chart (Battle::Types).
  def types = @data["types"] || Battle::Types::DEFAULT

  def units = @units ||= @data["units"].map { |unit| BattleUnit.new(unit) }
  def unit(id) = units.find { |unit| unit.id == id }

  # A side's units still on the field (KO'd included: they're lying there).
  def on_field(side) = units.select { |unit| unit.side == side && unit.on_field? }

  # Whoever could be aimed at: standing and on the field.
  def targetable = units.select { |unit| unit.standing? && unit.on_field? }

  def unit_name(id) = unit(id)&.name || id.to_s.humanize

  # The round's commands so far, by unit id: { "kind", "ability", "target", ... }.
  def commands = @data["inputs"] || {}
  def command_for(unit) = commands[unit.is_a?(BattleUnit) ? unit.id : unit]
  def chosen?(unit) = commands.key?(unit.id)

  # Players' ideas ("Try something") the GM hasn't ruled on: the round, and its clock, wait for them.
  def ideas_awaiting_ruling = commands.select { |_, command| command["kind"] == "custom" && !command["ruling"] }

  # The books' entries the battle copied in, by id.
  def abilities = @data["abilities"]
  def ability(id) = abilities[id]
  def items = @data.fetch("items", {})

  def ability_name(id) = ability(id)&.dig("name") || id.to_s.humanize
  def item_name(id) = items.dig(id, "name") || id.to_s.humanize

  # The engine's answers (Battle::State), asked of this state.
  def awaiting_input = Battle::State.awaiting_input(@data)
  def able_to_act?(unit) = Battle::State.able_to_act(@data).include?(unit.id)
  def usable?(unit, ability) = Battle::State.usable?(unit.to_h, ability)
  def target_options(unit, move) = Battle::State.target_options(@data, unit.to_h, move)
  def items_left(item_id, except: nil) = Battle::State.items_left(@data, item_id, except: except)
end
