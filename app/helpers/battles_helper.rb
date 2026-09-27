# frozen_string_literal: true

module BattlesHelper
  # The book entry whose image stands for a unit: its monster, or its
  # job for party members. Loaded once per render.
  def unit_art(battle, unit)
    @unit_art ||= {}
    @unit_art[battle.id] ||= {
      "monsters" => battle.world.monsters.with_attached_image.index_by(&:slug),
      "jobs" => battle.world.jobs.with_attached_image.index_by(&:slug)
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
      tag.span(unit["name"].to_s.first, class: "sprite__plate", style: style)
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
    AFFINITY_LABELS.each do |affinity, label|
      names = target.fetch("elements", {}).select { |_, a| a == affinity }.keys
      names += target.fetch("status_immune", []) if affinity == "immune"
      facts << "#{label} #{names.map { |n| term(n) }.to_sentence}" if names.any?
    end
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

  # One line of the battle log for an event, or nil for bookkeeping events
  # the log doesn't show. The log only ever describes; the resolver decided.
  def battle_log_line(event, state)
    name = ->(key) { unit_name(state, event[key]) }
    case event["type"]
    when "round_start" then "— Round #{event['round']} —"
    when "attack" then "#{name.('actor')} attacks."
    when "cast"
      verb = state["abilities"].dig(event["ability"], "kind") == "magic" ? "casts" : "uses"
      "#{name.('actor')} #{verb} #{ability_name(state, event['ability'])}."
    when "item_used" then "#{name.('actor')} uses #{item_phrase(event['name'])}."
    when "crit" then "Critical hit!"
    when "damage" then damage_line(event, name.("target"))
    when "heal" then event["absorbed"] ? "#{name.('target')} absorbs #{event['amount']} HP." : "#{name.('target')} recovers #{event['amount']} HP."
    when "miss" then miss_line(event, name.("target"), state)
    when "status_applied" then "#{name.('target')}: #{event['status'].humanize}."
    when "status_expired" then status_expired_line(event, name.("target"))
    when "buff_applied"
      "#{name.('target')}'s #{stat_label(event['stat'])} #{event['amount'].positive? ? 'rises' : 'falls'}."
    when "buff_expired" then "#{name.('target')}'s #{stat_label(event['stat'])} returns to normal."
    when "ko" then state["units"].find { |u| u["id"] == event["target"] }&.dig("side") == "party" ? "#{name.('target')} is down!" : "#{name.('target')} is defeated."
    when "revive" then "#{name.('target')} is back on their feet."
    when "defend" then "#{name.('actor')} defends."
    when "flee" then flee_line(event)
    when "turn_skipped" then skipped_line(event, name.("unit"))
    when "action_failed" then action_failed_line(event, name.("actor"), state)
    when "timeout" then "Time's up! #{event['defaulted'].map { |id| unit_name(state, id) }.to_sentence} act on reflex." if event["defaulted"].any?
    when "victory" then victory_line(event)
    when "defeat" then "The party has fallen…"
    when "gm_override" then gm_line(event, state)
    end
  end

  def item_name(state, id)
    state.fetch("items", {}).dig(id, "name") || id.to_s.humanize
  end

  private

  def damage_line(event, target)
    return "#{target} takes #{event['amount']} poison damage." if event["status"] == "poison"

    line = "#{target} takes #{event['amount']} damage."
    event["weak"] ? "#{line} It's super effective!" : line
  end

  def miss_line(event, target, state)
    case event["reason"]
    when "evaded" then "#{target} dodges."
    when "immune" then "#{target} is unaffected."
    when "resisted" then "#{target} resists #{event['status'].to_s.humanize}."
    when "not_ko" then "#{target} is already standing."
    when "nothing_to_cure" then "#{target} has nothing to cure."
    else "#{event['item'] ? item_name(state, event['item']) : ability_name(state, event['ability'])} has no target."
    end
  end

  def status_expired_line(event, target)
    case event["reason"]
    when "woke" then "#{target} wakes up."
    when "cured" then "#{target} is cured of #{event['status'].humanize.downcase}."
    when "gm" then nil # the gm_override line already said it
    else "#{target}'s #{event['status'].humanize} wears off."
    end
  end

  def action_failed_line(event, actor, state)
    case event["reason"]
    when "silenced" then "#{actor} is silenced!"
    when "no_item" then "There's no #{item_name(state, event['item'])} left."
    else "#{actor} doesn't have the MP."
    end
  end

  # "a Potion", "an Antidote", "an Echo Screen".
  def item_phrase(name)
    "#{name.to_s.match?(/\A[aeiou]/i) ? 'an' : 'a'} #{name}"
  end

  def flee_line(event)
    return "The party escapes!" if event["success"]

    event["reason"] == "no_escape" ? "There's no escape!" : "Couldn't get away!"
  end

  def skipped_line(event, unit)
    case event["reason"]
    when "sleep" then "#{unit} is asleep."
    when "paralyze" then "#{unit} can't move."
    else "#{unit} has no orders."
    end
  end

  def victory_line(event)
    rewards = event["rewards"].to_h.slice("exp", "gil", "abp").select { |_, v| v.to_i.positive? }
    spoils = rewards.map { |k, v| "#{v} #{k == 'gil' ? 'gil' : k.upcase}" }.to_sentence
    spoils.present? ? "Victory! #{spoils}." : "Victory!"
  end

  # GM power is never hidden (§12): every override gets a log line.
  def gm_line(event, state)
    who = unit_name(state, event["unit"]) if event["unit"]
    text = case event["op"]
    when "auto" then "plays #{event['units'] ? event['units'].map { |id| unit_name(state, id) }.to_sentence : who} on auto."
    when "execute_round" then "runs the round now."
    when "set_hp" then "sets #{who}'s HP to #{event['hp']}."
    when "set_mp" then "sets #{who}'s MP to #{event['mp']}."
    when "add_status" then "inflicts #{event['status'].to_s.humanize} on #{who}."
    when "remove_status" then "cures #{who}'s #{event['status'].to_s.humanize}."
    when "end_battle" then "ends the battle: #{event['result']}."
    else event["op"].to_s.humanize
    end
    [ "GM #{text}", (%("#{event['note']}") if event["note"].present?) ].compact.join(" ")
  end
end
