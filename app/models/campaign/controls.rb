# frozen_string_literal: true

# The table's controls: what kind of moment the GM has called, and so which
# actions everyone sees (docs/DESIGN.md, "Players steer"). The GM calls it
# from the Now line; the table's panels show what fits and nothing else.
#   talk    the floor: the dialogue, and nothing to pick (the default)
#   travel  the ways on: roads, a dungeon's door and rooms; the vote, for players
#   doing   things to do here this part of the day (Pastime), and the vote
# A battle, an encounter, a scene or an open choice still comes first: the
# controls say what the free table offers.
module Campaign::Controls
  extend ActiveSupport::Concern

  CONTROLS = %w[talk travel doing].freeze
  CONTROL_LABELS = { "talk" => "Talk", "travel" => "Travel", "doing" => "Things to do here" }.freeze

  included do
    validates :controls, inclusion: { in: CONTROLS }
  end

  def call_controls!(kind)
    raise Refusal, "There's no such thing to call at the table" unless CONTROLS.include?(kind)

    update!(controls: kind)
  end

  def travelling? = controls == "travel"
  def doing? = controls == "doing"

  # The ways on that fit the controls: in "talk", none are offered (the
  # table is talking); in "travel", the roads and rooms; in "doing", the
  # things to do here. A way that spends time is a pastime.
  def ways_offered(ways = ways_on)
    case controls
    when "travel" then ways.reject { |way| way.dig("move", "pastime") }
    when "doing" then ways.select { |way| way.dig("move", "pastime") }
    else []
    end
  end
end
