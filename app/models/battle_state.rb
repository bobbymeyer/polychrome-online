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

  # The round's commands so far, by unit id (BattleCommand).
  def commands = @commands ||= (@data["inputs"] || {}).transform_values { |command| BattleCommand.new(command) }
  def command_for(unit) = commands[unit.is_a?(BattleUnit) ? unit.id : unit]
  def chosen?(unit) = commands.key?(unit.id)

  # Players' ideas ("Try something") the GM hasn't ruled on, by unit id: the round, and its clock, wait for them.
  def ideas_awaiting_ruling = commands.select { |_, command| command.awaiting_ruling? }

  # What the battle copied in from the books (BattleMove): its abilities, and the party's items.
  def abilities = @abilities ||= @data["abilities"].transform_values { |ability| BattleMove.new(ability) }
  def ability(id) = abilities[id]
  def items = @items ||= @data.fetch("items", {}).transform_values { |item| BattleMove.new(item, item: true) }
  def item(id) = items[id]

  def ability_name(id) = ability(id)&.name || id.to_s.humanize
  def item_name(id) = item(id)&.name || id.to_s.humanize

  # A unit's own abilities, in its order.
  def abilities_of(unit) = unit.abilities.filter_map { |id| ability(id) }

  # The engine's answers (Battle::State), asked of this state.
  def awaiting_input = Battle::State.awaiting_input(@data)
  def able_to_act?(unit) = Battle::State.able_to_act(@data).include?(unit.id)
  def usable?(unit, ability) = Battle::State.usable?(unit.to_h, ability.to_h)
  def target_options(unit, move) = Battle::State.target_options(@data, unit.to_h, move.to_h)
  def items_left(item_id, except: nil) = Battle::State.items_left(@data, item_id, except: except)
end
