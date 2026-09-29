# frozen_string_literal: true

# When the whole party is down, the GM decides what the story does with it
# (docs/DESIGN.md, "Defeat"). Three ways on, each told at the table:
#
#   retreat   — they come to in the nearest town, rested, and poorer: half
#               the party's money is gone (Dragon Quest's way)
#   get_up    — somehow everyone gets up where they fell, with 1 HP
#   game_over — the story ends here; the party stays down
module Campaign::Defeat
  extend ActiveSupport::Concern

  RECOVERIES = %w[retreat get_up game_over].freeze

  def wiped_out?
    characters.any? && characters.none?(&:conscious?)
  end

  # The town the party wakes up in: the nearest by road from where they
  # fell, or any town on the map. Nil if there isn't one.
  def refuge
    towns = map_nodes.where(visible: true, kind: "town").order(:id).to_a
    return if towns.empty?
    return towns.first unless current_node

    roads = map_edges.to_a
    seen = { current_node.id => true }
    frontier = [ current_node.id ]
    until frontier.empty?
      town = towns.find { |node| frontier.include?(node.id) }
      return town if town

      frontier = frontier.flat_map do |id|
        roads.filter_map do |road|
          if road.from_node_id == id then road.to_node_id
          elsif road.to_node_id == id then road.from_node_id
          end
        end
      end.uniq.reject { |id| seen[id] }
      frontier.each { |id| seen[id] = true }
    end
    towns.first
  end

  def recover!(how)
    raise Refusal, "Pick what happens next" unless RECOVERIES.include?(how)
    raise Refusal, "Not while a battle is on" if battle_on?
    raise Refusal, "Someone is still standing" unless wiped_out?

    transaction do
      case how
      when "retreat" then retreat!
      when "get_up"
        characters.each { |character| character.update!(hp: 1) }
        narrate("Somehow, one by one, everyone gets back up.")
      when "game_over"
        narrate("The party has fallen. Their story ends here.")
      end
    end
    broadcast_party
    broadcast_map
  end

  private

  def retreat!
    town = refuge or raise Refusal, "There's no town on the map to retreat to"
    lost = gil / 2
    current_node&.location&.leave! unless current_node == town
    update!(current_node: town, gil: gil - lost, pending_encounter: nil)
    characters.update_all(hp: nil, mp: nil, field_used: false)
    narrate("The party comes to in #{town.name}, bruised but alive#{", #{money(lost)} lighter" if lost.positive?}.")
    pass_time!(until_dawn, announce: :new_day)
  end
end
