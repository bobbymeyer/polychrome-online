# frozen_string_literal: true

module Campaign::MonsterNotes
  extend ActiveSupport::Concern

  # What the party learns about monsters by fighting them (§ Play: weaknesses
  # are found, not given). An element that lands shows how the monster takes
  # it; a status it shrugs off shows it's immune, one that sticks that it
  # isn't; a scan shows everything. Kept per monster, across battles.
  def learn_from!(events, state)
    field = BattleState.new(state)
    units = field.units.index_by(&:id)
    learned = known_affinities.deep_dup
    events.each do |event|
      target = units[event["target"]]
      slug = target&.enemy? && target.image_slug
      next unless slug

      notes = (learned[slug] ||= {})
      if event["type"] == "scan"
        notes["types"] = target.types
        Battle::Types.list(field.types).each { |type| notes[type] = target.affinities.fetch(type, "none") }
        Battle::STATUSES.each { |kind| notes[kind] = target.status_immune.include?(kind) ? "immune" : "none" }
      elsif event["damage_type"]
        # Seeing a type land shows what the monster is: its types, and how it took this one.
        notes["types"] = target.types
        notes[event["damage_type"]] = target.affinities.fetch(event["damage_type"], "none")
      elsif event["type"] == "miss" && event["reason"] == "immune" && event["status"]
        notes[event["status"]] = "immune"
      elsif event["type"] == "status_applied"
        notes[event["status"]] = "none"
      end
    end
    update!(known_affinities: learned) if learned != known_affinities
  end
end
