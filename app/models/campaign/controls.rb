# frozen_string_literal: true

# The table's controls: what kind of moment the GM has called, and so which
# actions everyone sees (docs/DESIGN.md, "Players steer"). The GM calls it
# from the Now line; the table's panels show what fits and nothing else.
#   talk    the floor: the dialogue, and nothing to pick (the default)
#   travel  the ways on: roads, a dungeon's door and rooms; the vote, for players
#   doing   things to do here this part of the day (Pastime), and the vote
#   scene   the GM's scenes, to put one on the stage (nothing for players yet)
#   check   the GM's check form: who rolls what (the roll lands for everyone)
#   battle  the GM's battle setup: what they face, who fights, Start (BattleSetup)
#   tools   the rest of the GM's tools: the moves that are live, grants (nothing for players)
# A battle, an encounter, a scene on the stage or an open choice still comes
# first: the controls say what the free table offers. There is no other
# strip of GM tools for these: the one called is the one on the table.
module Campaign::Controls
  extend ActiveSupport::Concern

  CONTROLS = %w[talk travel doing scene check battle tools].freeze
  # Short names on the strip: Talk · Move · Do · Scene · Check · Fight · GM.
  CONTROL_LABELS = { "talk" => "Talk", "travel" => "Move", "doing" => "Do", "scene" => "Scene", "check" => "Check", "battle" => "Fight",
                     "tools" => "GM" }.freeze

  included do
    validates :controls, inclusion: { in: CONTROLS }
  end

  # Calling travel puts the map on the stage (Mapping#show_map!): the roads
  # are asked from it. The other calls leave the stage as it is.
  def call_controls!(kind)
    raise Refusal, "There's no such thing to call at the table" unless CONTROLS.include?(kind)

    transaction do
      update!(controls: kind)
      show_map! if kind == "travel" && party_map && !map_on_stage?
    end
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

  # What the table is doing right now, the first that holds: a battle holds
  # everything else, then a rolled encounter waiting for the GM's call, an
  # open choice, a scene on the stage, else free play. A player's moves
  # follow it (campaigns/tables/_now, stage.css).
  def table_state
    if battle_on? then "battle"
    elsif pending_encounter.present? then "encounter"
    elsif open_choice then "choice"
    elsif staged_scene&.current_beat then "scene"
    else "free"
    end
  end

  # The ways the party can pay for: a pastime here that costs more than the
  # purse holds is left out.
  def affordable(ways)
    prices = current_node ? current_node.pastimes.to_h { |pastime| [ pastime.name, pastime.price ] } : {}
    ways.reject { |way| (doing = way.dig("move", "pastime")) && prices[doing].to_i > gil }
  end
end
