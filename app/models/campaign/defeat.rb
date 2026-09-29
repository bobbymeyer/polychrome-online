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
    nearest_town(current_node) || map_nodes.where(visible: true, kind: "town").order(:id).first
  end

  def recover!(how)
    raise Refusal, "Pick what happens next" unless RECOVERIES.include?(how)
    raise Refusal, "Not while a battle is on" if battle_on?
    raise Refusal, "Someone is still standing" unless wiped_out?

    line = transaction do
      case how
      when "retreat" then retreat!
      when "get_up"
        characters.each { |character| character.update!(hp: 1) }
        narrate("Somehow, one by one, everyone gets back up.").body
      when "game_over"
        narrate("The party has fallen. Their story ends here.").body
      end
    end
    battles.where(status: "defeat").order(:id).last&.aftermath!(line)
    table_changed # the party got up, or moved: some changes skip callbacks
  end

  private

  def retreat!
    town = refuge or raise Refusal, "There's no town on the map to retreat to"
    lost = gil / 2
    current_node&.location&.leave! unless current_node == town
    update!(current_node: town, gil: gil - lost, pending_encounter: nil)
    characters.update_all(hp: nil, mp: nil, field_used: false)
    line = narrate("The party comes to in #{town.name}, bruised but alive#{", #{money(lost)} lighter" if lost.positive?}.").body
    pass_time!(until_dawn, announce: :new_day)
    line
  end
end
