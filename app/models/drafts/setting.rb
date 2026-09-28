# frozen_string_literal: true

module Drafts
  # A setting's types, skills and job ideas, from a pitch. Types and skills
  # can be kept straight into the world; jobs need numbers, so they're
  # ideas for the Compendium.
  class Setting < Base
    def instructions
      "You help set up a setting for a JRPG-style tabletop game. From the pitch, suggest damage types (like fire or " \
        "holy, but fitting this setting), skills for checks outside battle, each rolled on one stat " \
        "(#{Stats::Check::STATS.join(', ')}: strength, magic, vitality, spirit, agility), and jobs (character classes). " \
        'Reply with JSON: {"types": [{"name": "...", "colour": "#rrggbb"}], ' \
        '"skills": [{"name": "...", "stat": "one of the stats", "description": "one short sentence"}], ' \
        '"jobs": [{"name": "...", "description": "one short sentence", "type": "one of your types, or null"}]}, ' \
        "with 4 to 8 types, 6 to 8 skills and 6 to 10 jobs."
    end

    def context
      [ setting,
        "It has types: #{world.type_chart.types.map(&:name).join(', ')}.",
        "It has skills: #{world.skills.map { |s| s['name'] }.join(', ')}.",
        "It has jobs: #{world.jobs.alphabetical.limit(30).map(&:name).join(', ').presence || 'none'}.",
        ("Pitch: #{request['pitch']}" if request["pitch"].present?) ].compact.join("\n\n")
    end

    def items(json)
      types = rows(json, "types").filter_map do |t|
        name = clip(t["name"], 30)
        { "section" => "type", "name" => name, "colour" => t["colour"].to_s.match?(TypeChart::COLOUR) ? t["colour"] : TypeChart::NEW_COLOUR } unless name.empty?
      end
      skills = rows(json, "skills").filter_map do |s|
        name = clip(s["name"], 30)
        next if name.empty? || !Stats::Check::STATS.include?(s["stat"].to_s)

        { "section" => "skill", "name" => name, "stat" => s["stat"].to_s, "description" => clip(s["description"], 200) }
      end
      jobs = rows(json, "jobs").filter_map do |j|
        name = clip(j["name"], 40)
        { "section" => "job", "name" => name, "description" => clip(j["description"], 200), "type" => clip(j["type"], 30).presence }.compact unless name.empty?
      end
      types.first(10) + skills.first(10) + jobs.first(12)
    end

    def keep!(item)
      slug = item["name"].parameterize(separator: "_").sub(/\A[^a-z]+/, "")
      case item["section"]
      when "type"
        rows = world.damage_types + [ { "slug" => slug, "name" => item["name"], "colour" => item["colour"], "shrugs_off" => [], "against" => {} } ]
        change = TypeChange.new(world, rows: rows)
        raise ArgumentError, world.errors.full_messages.to_sentence unless change.save

        { notice: "#{item['name']} is one of #{world.name}'s types. Chart it on the Types page." }
      when "skill"
        world.update!(skills: world.skills + [ { "slug" => slug, "name" => item["name"], "stat" => item["stat"], "description" => item["description"] } ])
        { notice: "#{item['name']} is one of #{world.name}'s skills." }
      else
        raise ArgumentError, "A job needs its numbers: make it in the Compendium"
      end
    end
  end
end
