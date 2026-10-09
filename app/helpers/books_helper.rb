# frozen_string_literal: true

# Rendering helpers for book pages. Everything here is derived from the
# entry; nothing is stored (§12: rendering is derived, never the source).
module BooksHelper
  # An archetype's payoff, as a line: "40 gil a part of the day", "A rumour".
  def payoff_summary(job)
    payoff = job.payoff
    case payoff["kind"]
    when "rumour" then "A rumour, at the next rest"
    when "money" then "#{payoff['amount']} #{word('currency')} a part of the day, at the next rest"
    else "#{payoff['amount']} #{payoff['kind'].upcase} a part of the day, at the next rest"
    end
  end

  STAT_LABELS = {
    "max_hp" => "HP", "max_mp" => "MP", "str" => "Str", "mag" => "Mag", "vit" => "Vit",
    "spr" => "Spr", "agi" => "Agi", "atk" => "Atk", "def" => "Def", "mdef" => "MDef"
  }.freeze

  # A monster in a select, by how tough it is: its HP, which is what a fight
  # against it turns on. A Bestiary level is only its place in the book (a
  # world can make its first monster a real threat), so it isn't shown here.
  # "Goblin (81 HP)", "Goblin Chief (364 HP, boss)". by: :id or :slug.
  def monster_options(monsters, by: :slug)
    monsters.order(:level, :name).map { |m| [ "#{m.name} (#{m.stats['max_hp']} HP#{', boss' if m.boss?})", m.public_send(by) ] }
  end

  # Encounter tables for a select, with how tough what's in them is, so the
  # GM can match a road or dungeon to the party: "Grasslands (81–108 HP)".
  def encounter_table_options(world)
    hp = world.monsters.to_h { |m| [ m.slug, m.stats["max_hp"] ] }
    world.encounter_tables.order(:tier, :name).map do |table|
      found = table.entries.flat_map { |e| e["monsters"].keys }.filter_map { |slug| hp[slug] }.minmax.compact.uniq
      [ found.any? ? "#{table.name} (#{found.join('–')} HP)" : table.name, table.id ]
    end
  end

  # How a type (or pair) takes every type, from the chart and the unit's own
  # exceptions: { "weak" => [...], "resist" => [...], "immune" => [...],
  # "absorb" => [...] }, each in chart order. A character (character: true)
  # resists what the chart says they're immune to. engine: the chart to
  # read (a battle's own, Battle::Types); the world's when not given.
  def type_profile(types, affinities = {}, character: false, engine: nil)
    engine ||= type_chart.to_engine
    target = { "types" => Array(types), "affinities" => affinities || {}, "immune_as_resist" => character }
    Battle::Types.list(engine).each_with_object(Hash.new { |h, k| h[k] = [] }) do |attacking, profile|
      percent = Battle::Types.effectiveness(attacking, target, engine)
      band = if percent == :absorb then "absorb"
      elsif percent.zero? then "immune"
      elsif percent > 100 then "weak"
      elsif percent < 100 then "resist"
      end
      profile[band] << attacking if band
    end
  end

  # The world on the page's types (World#type_chart), once per request.
  def type_chart(world = nil)
    world ||= @world || @battle&.world || @campaign&.world || @character&.world
    @type_charts ||= {}
    @type_charts[world&.id] ||= world ? world.type_chart : TypeChart.new(TypeChart.default_rows)
  end

  # Is this a world where types come up at all? Not with only one.
  def types_matter?(world = nil)
    type_chart(world).matter?
  end

  def type_name(type)
    type_chart.name(type)
  end

  # [name, slug] pairs for a select.
  def type_options
    type_chart.types.map { |t| [ t.name, t.slug ] }
  end

  # A type as a tag in its colour.
  def type_tag(type)
    chart = type_chart
    tag.span(chart.name(type), class: "type-tag", style: "--t: #{chart.colour(type)}; --t-ink: var(--#{chart.ink(type)})")
  end

  def stat_label(name)
    worlds_label(name.to_s) || STAT_LABELS.fetch(name.to_s, name.to_s.humanize)
  end

  # A character as a picture: their own portrait, or their job's (a
  # lettered plate when the job has none either).
  def character_portrait(character, size: :large)
    image = character.own_portrait_image("neutral")
    return entry_portrait(character.job, size: size) unless image

    tag.figure(class: [ "portrait", "portrait--#{size}" ]) { image_tag(url_for(image), alt: character.name) }
  end

  # The entry's image with its variant recipe applied, or a placeholder
  # plate when no image has been attached yet.
  def entry_portrait(entry, size: :large)
    classes = [ "portrait", "portrait--#{size}" ]
    # An upload on a form that failed validation isn't stored yet, so it
    # can't be shown; fall back to the plate.
    if entry.image.attached? && entry.image.blob.persisted?
      tag.figure(class: classes) do
        image_tag(url_for(entry.image), alt: entry.name, style: variant_style(entry.variant))
      end
    else
      tag.figure(class: classes + [ "portrait--empty" ], aria: { label: "No image yet" }, style: plate_style(entry.try(:slug) || entry.name, entry.try(:colour))) do
        tag.span(entry.name.to_s.first, style: variant_style(entry.variant), class: "portrait__initial")
      end
    end
  end

  def variant_style(variant)
    filters = []
    transforms = []
    filters << "hue-rotate(#{variant['hue'].to_i}deg)" if variant["hue"]
    transforms << "scale(#{variant['scale'].to_i / 100.0})" if variant["scale"]
    transforms << "scaleX(-1)" if variant["flip"]
    styles = []
    styles << "filter: #{filters.join(' ')}" if filters.any?
    styles << "transform: #{transforms.join(' ')}" if transforms.any?
    styles.join("; ").presence
  end

  # "Fire 20 ×2", "Poison 100% for 4", ... one line per effect.
  def describe_effect(effect)
    e = effect
    case e["primitive"]
    when "physical" then "#{"#{effect_type(e['type'])} " if e['type']}Physical #{e.fetch('power', 100)}%#{hits(e)}#{describe_against(e)}#{describe_extras(e)}"
    when "elemental" then "#{effect_type(e['type'])} damage, power #{e['power']}#{hits(e)}#{describe_against(e)}#{describe_extras(e)}"
    when "status" then "#{term(e['kind'])} (#{e.fetch('chance', 100)}%, #{e.fetch('duration', 3)} turns)"
    when "heal" then "Restore #{word('hp')}, power #{e['power']}#{", up to +#{e['triage']}% the lower the target" if e['triage'].to_i.positive?}"
    when "drain" then "Drain #{word('hp')}, power #{e['power']}"
    when "buff" then "#{stat_label(e['stat'])} +#{e['amount']}% for #{e.fetch('duration', 3)} turns"
    when "debuff" then "#{stat_label(e['stat'])} −#{e['amount']}% for #{e.fetch('duration', 3)} turns"
    when "revive" then "Revive at #{e.fetch('fraction', 25)}% #{word('hp')}"
    when "escape" then "Escape from battle"
    when "cleanse" then e["kind"] ? "Cure #{term(e['kind']).downcase}" : "Cure every harmful status"
    when "steal" then e["boon"] == 1 ? "Steal one of its good statuses (#{e.fetch('chance', 50)}% + speed)" : "Steal one of its drops (#{e.fetch('chance', 50)}% + speed)"
    when "scan" then "Reveal #{word('hp')}, weaknesses and immunities"
    when "jump" then "Leap out of reach, then land a #{e.fetch('power', 200)}% blow next turn"
    when "away" then describe_away(e)
    when "shield" then "A barrier against the next #{e['power']}-power worth of damage (#{e.fetch('duration', 3)} turns)"
    when "imbue" then "Attack strikes as #{effect_type(e['type']).downcase} (#{e.fetch('duration', 3)} turns)"
    when "percent" then "#{e['power']}% of current #{word('hp')}#{" (#{e['chance']}%)" if e['chance']}; never the last of it"
    when "summon"
      stays = if e["stays"] == 1 then "stays for the battle"
      elsif e.fetch("duration", 1).zero? then "stays while its summoner stands"
      else "stays #{pluralize(e.fetch('duration', 1), 'turn')}"
      end
      "Call #{@world&.monsters&.find_by(slug: e['creature'])&.name || e['creature'].to_s.humanize} (acts at once, #{stays}#{", #{e['power']}% strength" if e['power']})"
    when "gather" then "Gather #{pluralize(e.fetch('amount', 1), 'stack')} of #{term(e['kind']).downcase} (up to #{Battle::MAX_STACKS})"
    when "dispel" then "Take away its good statuses and raised stats"
    when "quick" then "The ally goes again at once (once a round)"
    when "mimic" then "The last move an ally made, again, free"
    when "transform" then "Put on #{@world&.items&.find_by(slug: e['mask'])&.name || e['mask'].to_s.humanize}"
    when "sap" then "Take #{word('mp')}, power #{e['power']}#{", keep #{e['keep']}%" if e['keep'].to_i.positive?}"
    else e["primitive"].to_s.humanize
    end
  end

  def describe_against(e)
    return "" unless e["against"]

    what = Battle::STATUSES.include?(e["against"]) || Battle::AGAINST_TRAITS.include?(e["against"]) ? term(e["against"]).downcase : type_name(e["against"])
    ", ×#{format('%g', e.fetch('bonus', 200) / 100.0)} against #{what}"
  end

  def describe_extras(e)
    [ (", the user takes #{e['recoil']}% of it" if e["recoil"].to_i.positive?),
      (", up to +#{e['grudge']}% power at the brink" if e["grudge"].to_i.positive?),
      (", ignores #{e['pierce']}% of defence" if e["pierce"].to_i.positive?),
      (", resistances count as neutral" if e["unresisted"] == 1),
      (", +#{e.fetch('boost', 50)}% for each stack of #{term(e['with']).downcase}#{e['hold'] == 1 ? ', kept' : ', spent'}" if e["with"]),
      (", +#{e['patience']}% for everyone who went first" if e["patience"].to_i.positive?) ].compact.join
  end

  def describe_away(e)
    turns = pluralize(e.fetch("duration", 1), "turn")
    if e["who"] == "self"
      e.fetch("power", 0).positive? ? "Out of reach for #{turns}, then a #{e['power']}% blow" : "Off the field for #{turns}, then back to act"
    else
      "Sent off the field for #{turns} (#{e.fetch('chance', 100)}%)"
    end
  end

  def effect_type(type)
    type == "terrain" ? "Terrain" : type_name(type)
  end

  # A reaction's moment (Battle::AI::TRIGGERS), or nil for a rule taken on the creature's turn.
  def describe_moment(trigger, by = nil)
    case trigger
    when "hit" then by ? "When hit by #{term(by)}" : "When hit"
    when "ally_falls" then "When one of its own falls"
    when "falls" then "With its last breath"
    end
  end

  def describe_condition(name, value)
    case name
    when "self_hp_below" then "own HP below #{value}%"
    when "ally_hp_below" then "an ally's HP below #{value}%"
    when "ally_ko" then value ? "an ally is KO'd" : "no ally is KO'd"
    when "round_multiple" then "every #{value.ordinalize} round"
    when "chance" then "#{value}% of the time"
    else "#{name} #{value}"
    end
  end

  # Field name for a JSON column key inside a form: monster[stats][str]
  def json_field_name(form, *keys)
    form.object_name + keys.map { |k| "[#{k}]" }.join
  end

  # Existing rows plus blank ones to fill in (no JS needed to add rows).
  def rows_with_blanks(rows, blanks: 2)
    rows + Array.new(blanks) { {} }
  end

  private

  def hits(effect)
    effect.fetch("hits", 1) > 1 ? " ×#{effect['hits']}" : ""
  end
end
