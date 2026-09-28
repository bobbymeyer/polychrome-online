# frozen_string_literal: true

module Drafts
  # A scene's script (Scene), from its bones. Kept, it goes onto the new
  # scene form for the GM to finish: its ending, and any line to fix.
  class Scene < Base
    def instructions
      "You write a short scene the GM will play at the table, as a script: one line each, " \
        "\"Name (expression): what they say\" for someone from the cast, \"Narrator: ...\" for narration. " \
        "Use only names from the cast, or Narrator. Expressions, optional: #{Portrait::EXPRESSIONS.join(', ')}. " \
        "At most 12 lines. It may end on a choice for the table: \"? Option | Option -> flag_name\". " \
        'Reply with JSON: {"name": "the scene\'s name", "script": "the lines, separated by \\n"}.'
    end

    def context = campaign_context

    def items(json)
      rows(json, "scenes").presence&.first(1).then { |found| found || [ json ] }.filter_map do |row|
        script = row["script"].is_a?(Array) ? row["script"].join("\n") : row["script"].to_s
        script = script.lines.map(&:strip).reject(&:empty?).first(16).join("\n")
        next if script.empty?

        check = campaign.scenes.new(name: clip(row["name"], 80).presence || "A scene", script: script, ending: "none")
        check.validate
        { "name" => check.name, "script" => script, "problems" => check.errors[:script] }.reject { |_, v| v.blank? }
      end
    end

    def keep!(item)
      { notice: "The scene is on the form: pick how it ends and save it.",
        path: routes.new_campaign_scene_path(campaign, scene: { name: item["name"], script: item["script"] }) }
    end
  end
end
