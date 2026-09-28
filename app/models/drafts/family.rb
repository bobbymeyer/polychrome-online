# frozen_string_literal: true

module Drafts
  # Names and descriptions for an ability family's four tiers
  # (AbilityFamily). Kept, they go onto the family form, numbers and all
  # still the author's.
  class Family < Base
    def instructions
      "You name an ability family for a JRPG: four tiers of one move that belong together, the way Fire, Fira, Firaga " \
        "and Firaja do. Tier 1 hits one target; tier 2 one target, harder; tier 3 every target; tier 4 every target, " \
        "hardest. Names should read as one family: a shared root, rising. " \
        'Reply with JSON: {"tiers": [{"name": "...", "description": "one short sentence"}, ...]} with exactly 4 tiers.'
    end

    def context
      shape = AbilityFamily::SHAPE_LABELS[request["shape"]] || request["shape"]
      what = request["shape"] == "hexer" ? "inflicts #{request['status']}" : ("of the #{world.type_chart.name(request['type'])} type" if request["type"].present?)
      [ setting, "Root: #{request['root'].presence || '(choose one)'}. Shape: #{shape}#{", #{what}" if what}." ].join("\n\n")
    end

    def items(json)
      tiers = rows(json, "tiers").first(4).map { |t| { "name" => clip(t["name"], 40), "description" => clip(t["description"], 200) } }
      return [] unless tiers.size == 4 && tiers.all? { |t| t["name"].present? }

      [ { "tiers" => tiers } ]
    end

    def keep!(item)
      tiers = item["tiers"].each_with_index.to_h { |t, i| [ i.to_s, t.slice("name", "description") ] }
      family = request.slice("shape", "type", "status", "job_id").merge("root" => request["root"].presence || item["tiers"].first["name"], "tiers" => tiers)
      { notice: "The names are on the form: check the numbers and write the family.",
        path: routes.new_world_grimoire_family_path(world, family: family) }
    end
  end
end
