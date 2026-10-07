# frozen_string_literal: true

module BattlesHelper
  # What stands for a unit: a party member's own portrait (their job's art
  # without one), an antagonist's, or its monster. Loaded once per render.
  def unit_art(battle, unit)
    @unit_art ||= {}
    @unit_art[battle.id] ||= {
      "monsters" => battle.world.monsters.with_attached_image.index_by(&:slug),
      "jobs" => battle.world.jobs.with_attached_image.index_by(&:slug),
      "npcs" => (battle.campaign&.npcs&.antagonists || Npc.none).to_h { |npc| [ npc.id.to_s, npc.battle_art ] },
      "characters" => (battle.campaign&.characters&.includes(:job, portraits: { image_attachment: :blob }) || Character.none)
                        .to_h { |character| [ character.battle_unit_id, character.battle_art ] }
    }
    @unit_art[battle.id].dig("characters", unit.id.to_s) || @unit_art[battle.id].dig(unit.image["book"], unit.image_slug)
  end

  def unit_sprite(battle, unit)
    entry = unit_art(battle, unit)
    style = entry && variant_style(entry.variant)
    if entry&.image&.attached?
      image_tag(url_for(entry.image), alt: "", class: "sprite__image", style: style, draggable: false)
    else
      tag.span(unit.name.to_s.first, class: "sprite__plate", style: [ plate_style(unit.image_slug || unit.name, entry.try(:colour)), style ].compact.join(" "))
    end
  end

  # The help line for a command (docs/DESIGN.md, "Play"): what it hits, what it
  # does, what it costs; or why it can't be used right now.
  def ability_help(unit, ability)
    cost = ability.mp_cost
    unless Battle::State.usable?(unit.to_h, ability.to_h)
      silenced = ability.magic? && unit.status("silence")
      return silenced ? "Silenced: no magic until it wears off." : "Not enough MP (needs #{cost}, you have #{unit.mp})."
    end

    parts = [ term(ability.target) ]
    parts.concat(ability.effects.map { |e| describe_effect(e) })
    parts << "#{cost} MP" if cost.positive?
    parts.join(" · ")
  end

  # The help line for an item: what it hits and does, and how many are left.
  def item_help(item, left)
    return "None left: the party has used or spoken for every #{item.name}." unless left.positive?

    [ term(item.target), *item.effects.map { |e| describe_effect(e) }, "#{left} left" ].join(" · ")
  end

  AFFINITY_LABELS = { "weak" => "Weak to", "resist" => "Resists", "immune" => "Immune to", "absorb" => "Absorbs" }.freeze

  # What you can see of a target: an ally's HP and MP. For an enemy, what the
  # Bestiary says (its level and affinities), but never its HP.
  def target_help(battle, field, id)
    target = field.unit(id)
    return "" unless target

    statuses = target.status_kinds.map(&:humanize)
    facts = if target.party?
      [ "HP #{target.hp}/#{target.max_hp}", "MP #{target.mp}" ]
    else
      enemy_facts(battle, target)
    end
    (facts + statuses).join(" · ")
  end

  def enemy_facts(battle, target)
    return [ "KO" ] if target.ko?

    level = battle && unit_art(battle, target).try(:level)
    facts = [ level ? "Level #{level}" : "Enemy" ]
    # In a campaign, players see only what the party has found out.
    known = battle&.campaign&.known_affinities&.fetch(target.image_slug.to_s, {})
    types = target.types
    # Once the party knows what a monster is, the chart tells them the rest.
    knows_type = types.any? && (known.nil? || known["types"].present?)
    engine = battle ? battle.field.types : Battle::Types::DEFAULT
    facts << "#{types.map { |t| type_name(t) }.join('/')} type" if knows_type && types_matter?
    profile = type_profile(knows_type ? types : [], target.affinities, engine: engine)
    AFFINITY_LABELS.each do |affinity, label|
      names = profile[affinity].dup
      names += target.status_immune if affinity == "immune"
      names &= (known.keys + (knows_type ? Battle::Types.list(engine) : [])) if known
      facts << "#{label} #{names.map { |n| type_or_status(n) }.to_sentence}" if names.any?
    end
    facts << "Weaknesses unknown" if known && known.empty?
    facts
  end

  # "Won't affect Wolf A": what the party knows of a target says this move
  # can't hurt it (the chart's no effect, or it drinks the type up). Only
  # from what's been found out, so it never gives a weakness away.
  def futile_note(battle, field, actor, move, target)
    return unless target.enemy? && target.standing?

    type = move_type(field, actor, move) or return
    known = battle&.campaign&.known_affinities&.fetch(target.image_slug.to_s, {})
    seen = known ? { "types" => Array(known["types"]), "affinities" => known.select { |_, v| %w[immune absorb].include?(v) } } : target.to_h
    percent = Battle::Types.effectiveness(type, seen, field.types)
    if percent == 0 then "Won't affect #{target.name}" # rubocop:disable Style/NumericPredicate -- may be :absorb
    elsif percent == :absorb then "#{target.name} absorbs it"
    end
  end

  # What the party knows a move will do to a target, beside "Won't work":
  # "Weak!" or "Resists", from the chart and what they've seen of the
  # target's types. Never more than they've found out.
  def edge_note(battle, field, actor, move, target)
    return unless target.enemy? && target.standing?

    type = move_type(field, actor, move) or return
    known = battle&.campaign&.known_affinities&.fetch(target.image_slug.to_s, nil) or return
    return if Array(known["types"]).empty? && !known.key?(type)

    seen = { "types" => Array(known["types"]), "affinities" => known.select { |_, v| %w[weak resist].include?(v) } }
    percent = Battle::Types.effectiveness(type, seen, field.types)
    return unless percent.is_a?(Integer) && percent != 100

    percent > 100 ? "Weak!" : "Resists"
  end

  # The type a move deals damage with, as the resolver will: its own, or
  # for Attack and the signature, the unit's (Battle::Resolver#own).
  def move_type(field, actor, move)
    effect = move.effects.find { |e| %w[physical elemental jump].include?(e["primitive"]) } or return
    return (effect["type"] == "terrain" ? field.terrain : effect["type"]) if effect["type"]
    return unless move.id == "attack" || move.id == actor.signature
    return if effect["primitive"] == "elemental"

    imbued = actor.status("imbued")&.dig("type") if move.id == "attack"
    imbued || actor.attack_type
  end

  # What a party member means to do this round, for the board's intent tag
  # (docs/DESIGN.md, "Motion with meaning"): "Chip → Slip Hound A". Nothing
  # for a unit on nobody's side of the plan (an enemy, the KO'd).
  def intent_label(field, unit)
    command = field.command_for(unit)
    return if command.nil? || !unit.party? || unit.ko?

    what = command.custom? ? "“#{command.text.to_s.truncate(24)}”" : command_name(field, command)
    target = command.target && command.target != unit.id ? " → #{field.unit_name(command.target)}" : ""
    "#{what}#{target}"
  end

  # What a command uses, by name: "Fire", "Potion", or its kind ("Defend").
  def command_name(field, command)
    if command.ability? then field.ability_name(command.ability)
    elsif command.item? then field.item_name(command.item)
    else command.kind.to_s.humanize
    end
  end

  # What lasts on a unit, in words, for the GM's rows: "Poison (2), Str +20%".
  def unit_conditions(unit)
    (unit.statuses.map { |s| "#{term(s['kind'])} (#{s['turns']})" } + unit.buffs.map { |b| "#{stat_label(b['stat'])} #{signed(b['amount'])}%" }).join(", ")
  end

  # Classes for what lasts on a unit and shows on its sprite: guarding the
  # party (aggro, cover), charged, barriered, off the field.
  def unit_marks(unit)
    kinds = unit.status_kinds
    [ ("is-guarding" if kinds.intersect?(Battle::AGGRO_STATUSES)), ("is-charged" if kinds.include?("charged")),
      ("is-shielded" if kinds.include?("shield")), ("is-away" if kinds.intersect?(Battle::OUT_OF_REACH_STATUSES)),
      ("is-doomed" if kinds.include?("doom")) ].compact.join(" ")
  end

  # What a unit does if the round's clock runs out before they choose
  # (Battle::Resolver.default_command): their last command again if it
  # still works, else Attack. Said as the panel's warning.
  def timeout_command(field, unit)
    last = unit.last_command
    return "Attack" unless last&.ability? && last.ability != "attack"

    "#{field.ability_name(last.ability)} again (or Attack, if it can't)"
  end
end
