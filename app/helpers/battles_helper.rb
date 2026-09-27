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

  # One line of the battle log for an event, or nil for bookkeeping events
  # the log doesn't show. The log only ever describes; the resolver decided.
  def battle_log_line(event, state)
    name = ->(key) { unit_name(state, event[key]) }
    case event["type"]
    when "round_start" then "— Round #{event['round']} —"
    when "attack" then "#{name.('actor')} attacks."
    when "unit_joined" then event["guest"] ? "#{event['name']} joins the party!" : "#{event['name']} joins the fight!"
    when "unit_left" then "#{event['name']} leaves the field."
    when "custom_action" then "#{name.('actor')} tries: “#{event['text']}”#{" at #{unit_name(state, event['target'])}" if event['target']}"
    when "custom_roll" then "#{event['success'] ? 'It works!' : 'No luck.'} #{event['line'].presence}".strip + dice_note(event).to_s
    when "custom_unruled" then "No ruling in time: #{name.('actor')} attacks instead."
    when "jump" then "#{name.('actor')} leaps out of reach!"
    when "away" then event["unit"] == event["actor"] ? "#{name.('actor')} slips off the field." : "#{name.('unit')} is sent off the field!"
    when "back" then "#{name.('unit')} is back."
    when "shielded" then "#{name.('target')}'s barrier takes #{event['absorbed']}#{event['left'].zero? ? ' and breaks' : ''}."
    when "confused" then event["target"] ? "#{name.('actor')}, confused, turns on #{name.('target')}!" : "#{name.('actor')} stumbles about."
    when "mp_lost" then "#{name.('target')} loses #{event['amount']} MP."
    when "land" then event["target"] ? "#{name.('actor')} comes down on #{name.('target')}!" : "#{name.('actor')} lands, with nobody to hit."
    when "covered" then "#{name.('unit')} steps in front of #{unit_name(state, event['for'])}!"
    when "counter" then "#{name.('actor')} strikes back!#{dice_note(event)}"
    when "second_wind" then "#{name.('target')} gets back up! (Second Wind)"
    when "mp_restored" then "#{name.('target')} recovers #{event['amount']} MP."
    when "desperation" then "#{name.('actor')}, at the end of their rope: #{event['name']}!"
    when "cast"
      verb = state["abilities"].dig(event["ability"], "kind") == "magic" ? "casts" : "uses"
      "#{name.('actor')} #{verb} #{ability_name(state, event['ability'])}."
    when "item_used" then "#{name.('actor')} uses #{item_phrase(event['name'])}."
    when "crit" then "Critical hit!#{dice_note(event)}"
    when "damage" then damage_line(event, name.("target"))
    when "heal"
      if event["absorbed"] then "#{name.('target')} absorbs #{event['amount']} HP."
      elsif event["regen"] then "#{name.('target')} regenerates #{event['amount']} HP."
      else "#{name.('target')} recovers #{event['amount']} HP."
      end
    when "miss" then miss_line(event, name.("target"), state)
    when "status_applied" then "#{name.('target')}: #{event['status'].humanize}.#{dice_note(event)}"
    when "status_expired" then status_expired_line(event, name.("target"))
    when "buff_applied"
      "#{name.('target')}'s #{stat_label(event['stat'])} #{event['amount'].positive? ? 'rises' : 'falls'}."
    when "buff_expired" then "#{name.('target')}'s #{stat_label(event['stat'])} returns to normal."
    when "ko" then state["units"].find { |u| u["id"] == event["target"] }&.dig("side") == "party" ? "#{name.('target')} is down!" : "#{name.('target')} is defeated."
    when "revive" then "#{name.('target')} is back on their feet."
    when "defend" then "#{name.('actor')} defends."
    when "steal" then "#{name.('actor')} stole #{event['name']} from #{name.('target')}!#{dice_note(event)}"
    when "scan" then scan_line(event, name.("target"), state["types"] || Battle::Types::DEFAULT)
    when "flee" then "#{flee_line(event)}#{dice_note(event)}"
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
    return "#{line} Healing burns the undead!" if event["undead"]

    effectiveness = event["effectiveness"] || (event["weak"] ? 200 : 100) # "weak": battles from before types
    if effectiveness > 100 then "#{line} It's super effective!"
    elsif effectiveness < 100 then "#{line} It's not very effective…"
    else line
    end
  end

  def miss_line(event, target, state)
    case event["reason"]
    when "evaded" then "#{target} dodges.#{dice_note(event)}"
    when "immune" then event["damage_type"] ? "It doesn't affect #{target}…" : "#{target} is unaffected."
    when "resisted" then "#{target} resists #{event['status'].to_s.humanize}.#{dice_note(event)}"
    when "not_ko" then "#{target} is already standing."
    when "nothing_to_cure" then "#{target} has nothing to cure."
    when "nothing_to_steal" then "#{target} has nothing to steal."
    when "steal_failed" then "Couldn't steal from #{target}.#{dice_note(event)}"
    when "no_effect" then "#{target} barely feels it."
    when "no_mp" then "#{target} has no MP to take."
    else "#{event['item'] ? item_name(state, event['item']) : ability_name(state, event['ability'])} has no target."
    end
  end

  # A name in an affinity list: a type's (the world's name for it), or a
  # status's.
  def type_or_status(token)
    Battle::STATUSES.include?(token) ? term(token) : type_name(token)
  end

  def scan_line(event, target, engine = Battle::Types::DEFAULT)
    types = Array(event["types"])
    profile = type_profile(types, event["affinities"] || {}, engine: engine)
    facts = AFFINITY_LABELS.filter_map do |affinity, label|
      names = profile[affinity].dup
      names += event["status_immune"] if affinity == "immune"
      "#{label.downcase} #{names.map { |n| type_or_status(n).downcase }.to_sentence}" if names.any?
    end
    kind = types.any? && types_matter? ? ", #{types.map { |t| type_name(t) }.join('/')} type" : ""
    "#{target}: HP #{event['hp']}/#{event['max_hp']}#{kind}#{facts.any? ? ", #{facts.join(', ')}" : ', no weaknesses'}."
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

  # The d100 behind an outcome, for the log: " (rolled 98, needed 90 or under)".
  def dice_note(event)
    " (rolled #{event['roll']}, needed #{event['needed']} or under)" if event["roll"]
  end

  def flee_line(event)
    return "The party escapes!" if event["success"]

    event["reason"] == "no_escape" ? "There's no escape!" : "Couldn't get away!"
  end

  def skipped_line(event, unit)
    case event["reason"]
    when "sleep" then "#{unit} is asleep."
    when "paralyze" then "#{unit} can't move."
    when "away" then "#{unit} is away."
    when "stop" then "#{unit} is stopped in time."
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
    when "add_unit" then event["side"] == "party" ? "brings in #{who} to fight beside the party." : "brings in #{who}."
    when "dismiss" then "sends #{who} off."
    when "rule" then "rules on #{who}'s idea: #{stat_label(event['stat'])}, #{event['difficulty']}."
    else event["op"].to_s.humanize
    end
    [ "GM #{text}", (%("#{event['note']}") if event["note"].present?) ].compact.join(" ")
  end
end
