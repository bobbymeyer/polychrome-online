# frozen_string_literal: true

module BattlesHelper
  # The book entry whose image stands for a unit: its monster, or its
  # job for party members. Loaded once per render.
  def unit_art(battle, unit)
    @unit_art ||= {}
    @unit_art[battle.id] ||= {
      "monsters" => battle.world.monsters.with_attached_image.index_by(&:slug),
      "jobs" => battle.world.jobs.with_attached_image.index_by(&:slug),
      "npcs" => (battle.campaign&.npcs&.antagonists || Npc.none).to_h { |npc| [ npc.id.to_s, npc.battle_art ] }
    }
    ref = unit["image"] || {}
    @unit_art[battle.id].dig(ref["book"], ref["slug"])
  end

  def unit_sprite(battle, unit)
    entry = unit_art(battle, unit)
    style = entry && variant_style(entry.variant)
    if entry&.image&.attached?
      image_tag(url_for(entry.image), alt: "", class: "sprite__image", style: style, draggable: false)
    else
      tag.span(unit["name"].to_s.first, class: "sprite__plate", style: [ plate_style(unit.dig("image", "slug") || unit["name"], entry.try(:colour)), style ].compact.join(" "))
    end
  end

  # The help line for a command (docs/DESIGN.md, "Play"): what it hits, what it
  # does, what it costs; or why it can't be used right now.
  def ability_help(unit, ability)
    cost = Battle::State.ability_cost(ability)
    unless Battle::State.usable?(unit, ability)
      silenced = ability["kind"] == "magic" && unit["statuses"].any? { |s| s["kind"] == "silence" }
      return silenced ? "Silenced: no magic until it wears off." : "Not enough MP (needs #{cost}, you have #{unit['mp']})."
    end

    parts = [ term(ability["target"]) ]
    parts.concat(ability["effects"].map { |e| describe_effect(e) })
    parts << "#{cost} MP" if cost.positive?
    parts.join(" · ")
  end

  # The help line for an item: what it hits and does, and how many are left.
  def item_help(item, left)
    return "None left: the party has used or spoken for every #{item['name']}." unless left.positive?

    [ term(item["target"]), *item["effects"].map { |e| describe_effect(e) }, "#{left} left" ].join(" · ")
  end

  AFFINITY_LABELS = { "weak" => "Weak to", "resist" => "Resists", "immune" => "Immune to", "absorb" => "Absorbs" }.freeze

  # What you can see of a target: an ally's HP and MP. For an enemy, what the
  # Bestiary says (its level and affinities), but never its HP.
  def target_help(battle, state, id)
    target = state["units"].find { |u| u["id"] == id }
    return "" unless target

    statuses = target["statuses"].map { |s| s["kind"].humanize }
    facts = if target["side"] == "party"
      [ "HP #{target['hp']}/#{target['stats']['max_hp']}", "MP #{target['mp']}" ]
    else
      enemy_facts(battle, target)
    end
    (facts + statuses).join(" · ")
  end

  def enemy_facts(battle, target)
    return [ "Down" ] if target["hp"].zero?

    level = battle && unit_art(battle, target).try(:level)
    facts = [ level ? "Level #{level}" : "Enemy" ]
    # In a campaign, players see only what the party has found out.
    known = battle&.campaign&.known_affinities&.fetch(target.dig("image", "slug").to_s, {})
    types = target.fetch("types", [])
    # Once the party knows what a monster is, the chart tells them the rest.
    knows_type = types.any? && (known.nil? || known["types"].present?)
    engine = battle&.state&.dig("types") || Battle::Types::DEFAULT
    facts << "#{types.map { |t| type_name(t) }.join('/')} type" if knows_type && types_matter?
    profile = type_profile(knows_type ? types : [], target.fetch("affinities", {}), engine: engine)
    AFFINITY_LABELS.each do |affinity, label|
      names = profile[affinity].dup
      names += target.fetch("status_immune", []) if affinity == "immune"
      names &= (known.keys + (knows_type ? Battle::Types.list(engine) : [])) if known
      facts << "#{label} #{names.map { |n| type_or_status(n) }.to_sentence}" if names.any?
    end
    facts << "Weaknesses unknown" if known && known.empty?
    facts
  end

  def hp_percent(unit)
    (100.0 * unit["hp"] / unit["stats"]["max_hp"]).round
  end

  def hp_band(unit)
    pct = hp_percent(unit)
    if pct.zero? then "ko"
    elsif pct <= 25 then "danger"
    elsif pct <= 50 then "warn"
    else "ok"
    end
  end

  def unit_name(state, id)
    state["units"].find { |u| u["id"] == id }&.dig("name") || id.to_s.humanize
  end

  def ability_name(state, id)
    state["abilities"].dig(id, "name") || id.to_s.humanize
  end

  def item_name(state, id)
    state.fetch("items", {}).dig(id, "name") || id.to_s.humanize
  end
end
