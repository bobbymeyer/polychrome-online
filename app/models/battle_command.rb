# frozen_string_literal: true

# What a unit means to do this round, as its player (or the GM's auto)
# chose it: an ability, an item, defend, flee, or an idea of the player's
# own ("Try something") for the GM to rule on. Read from the round's inputs
# in the resolver's state (BattleState#command_for), and from a unit's last
# command, which is its default when the clock runs out.
class BattleCommand
  def initialize(data)
    @data = data
  end

  # The engine's own hash, for the engine.
  def to_h = @data

  # "ability", "item", "custom", "defend" or "flee".
  def kind = @data["kind"]
  def ability? = kind == "ability"
  def item? = kind == "item"
  def custom? = kind == "custom"

  def ability = @data["ability"]
  def item = @data["item"]
  # The unit it's aimed at, if one was picked.
  def target = @data["target"]
  def timing = @data["timing"]

  # A custom command's idea in words, and the GM's ruling on it once there is one: { "stat", "difficulty", ... }.
  def text = @data["text"]
  def ruling = @data["ruling"]
  def ruled? = ruling.present?
  def awaiting_ruling? = custom? && !ruled?

  def ==(other) = other.is_a?(BattleCommand) && other.to_h == to_h
  alias eql? ==
  def hash = @data.hash
end
