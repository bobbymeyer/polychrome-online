# frozen_string_literal: true

# Rendering helpers for book pages. Everything here is derived from the
# entry; nothing is stored (§12: rendering is derived, never the source).
module BooksHelper
  STAT_LABELS = {
    "max_hp" => "HP", "max_mp" => "MP", "str" => "Str", "mag" => "Mag", "vit" => "Vit",
    "spr" => "Spr", "agi" => "Agi", "atk" => "Atk", "def" => "Def", "mdef" => "MDef"
  }.freeze

  # Encounter tables for a select, with the levels of what's in them, so the
  # GM can match a road or dungeon to the party: "Grasslands (Lv 1–2)".
  def encounter_table_options(world)
    levels = world.monsters.to_h { |m| [ m.slug, m.level ] }
    world.encounter_tables.order(:tier, :name).map do |table|
      found = table.entries.flat_map { |e| e["monsters"].keys }.filter_map { |slug| levels[slug] }.minmax.compact.uniq
      [ found.any? ? "#{table.name} (Lv #{found.join('–')})" : table.name, table.id ]
    end
  end

  def stat_label(name)
    STAT_LABELS.fetch(name.to_s, name.to_s.humanize)
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
    when "physical" then "Physical #{e.fetch('power', 100)}%#{hits(e)}"
    when "elemental" then "#{term(e['element'])} damage, power #{e['power']}#{hits(e)}"
    when "status" then "#{term(e['kind'])} (#{e.fetch('chance', 100)}%, #{e.fetch('duration', 3)} turns)"
    when "heal" then "Restore HP, power #{e['power']}"
    when "drain" then "Drain HP, power #{e['power']}"
    when "buff" then "#{stat_label(e['stat'])} +#{e['amount']}% for #{e.fetch('duration', 3)} turns"
    when "debuff" then "#{stat_label(e['stat'])} −#{e['amount']}% for #{e.fetch('duration', 3)} turns"
    when "revive" then "Revive at #{e.fetch('fraction', 25)}% HP"
    when "escape" then "Escape from battle"
    when "cleanse" then e["kind"] ? "Cure #{term(e['kind']).downcase}" : "Cure every harmful status"
    when "steal" then "Steal one of its drops (#{e.fetch('chance', 50)}% + speed)"
    when "scan" then "Reveal HP, weaknesses and immunities"
    else e["primitive"].to_s.humanize
    end
  end

  def describe_condition(name, value)
    case name
    when "self_hp_below" then "own HP below #{value}%"
    when "ally_hp_below" then "an ally's HP below #{value}%"
    when "ally_ko" then value ? "an ally is down" : "no ally is down"
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
