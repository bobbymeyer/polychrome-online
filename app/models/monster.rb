# frozen_string_literal: true

# Bestiary entry: a stat block, a base type (Battle::Types) with any
# affinities that break the type chart, an FF-style AI script
# (ordered condition/action rules, §5), rewards and a drop table. The
# engine reads the entry through #to_engine; enemies in a battle are
# instances of it.
class Monster < ApplicationRecord
  include BookEntry
  include Colourable

  validates :level, numericality: { only_integer: true, greater_than: 0 }
  validates :exp, :gil, :abp, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :stat_block_is_complete
  before_validation :default_to_plain_type, on: :create
  validates :base_type, inclusion: { in: ->(monster) { monster.world_types }, message: "isn't one of this world's types" }
  validate :affinities_are_affinities
  validate :status_immunities_are_statuses
  validate :ai_script_is_valid
  validate :drops_are_items
  validate :phases_are_forms
  # Every battle takes the whole Grimoire and every table may roll it: an entry something still
  # names can't go, or the summon, the table and the lair would all break (Battle::State.build).
  before_destroy :still_needed

  def stats=(values)
    super((values || {}).to_h.stringify_keys.transform_values { |v| JsonCasting.integer(v) }.compact)
  end

  # Only the exceptions are stored: blank or "normal" means the chart decides.
  def affinities=(values)
    super((values || {}).to_h.stringify_keys.transform_values(&:to_s).reject { |_, v| v.blank? || v == "normal" })
  end

  def status_immune=(values)
    super(Array(values).map(&:to_s).compact_blank.uniq)
  end

  # Accepts engine-shaped rules ({ "if" => {...}, "use", "target" }) or flat
  # form rows ({ "use", "target", "self_hp_below" => "30", ... }).
  def ai_script=(rows)
    super(JsonCasting.rows(rows).filter_map do |row|
      next if row["use"].blank?

      conditions = row.fetch("if") { row.slice(*Battle::AI::CONDITIONS) }.to_h.stringify_keys
      conditions = conditions.filter_map do |name, value|
        next if value.blank? || value == "0" && name == "ally_ko"

        [ name, name == "ally_ko" ? ActiveModel::Type::Boolean.new.cast(value) : JsonCasting.integer(value) ]
      end.to_h
      # once: the rule fires one time a battle; say: a line said as it fires (the telegraph);
      # when: a reaction (hit, ally_falls, falls), by: the type of blow a hit reaction answers.
      { "if" => conditions.presence, "use" => row["use"].to_s, "target" => row["target"].presence,
        "once" => (true if ActiveModel::Type::Boolean.new.cast(row["once"])), "say" => row["say"].to_s.strip.presence,
        "when" => row["when"].presence, "by" => (row["by"].presence if row["when"] == "hit") }.compact
    end)
  end

  # Phases: [{ "hp_below" => 50, "becomes" => slug, "say" => "…", "restore" => 10 }], in order.
  # Below that share of its HP the creature becomes the entry named: its name, look, stats and script.
  def phases=(rows)
    super(JsonCasting.rows(rows).filter_map do |row|
      next if row["becomes"].blank?

      { "hp_below" => JsonCasting.integer(row["hp_below"]), "becomes" => row["becomes"].to_s, "say" => row["say"].to_s.strip.presence,
        "restore" => JsonCasting.integer(row["restore"]) || 0 }.compact
    end)
  end

  # The entries it becomes, in order.
  def forms
    by_slug = world.monsters.where(slug: phases.map { |p| p["becomes"] }).index_by(&:slug)
    phases.filter_map { |p| by_slug[p["becomes"]] }
  end

  # The entries whose phases become it.
  def form_of
    world.monsters.alphabetical.select { |m| m.phases.any? { |p| p["becomes"] == slug } }
  end

  def drops=(rows)
    super(JsonCasting.rows(rows).filter_map do |row|
      next if row["item"].blank?

      { "item" => row["item"].to_s, "chance" => JsonCasting.integer(row["chance"]) || 100 }
    end)
  end

  # Abilities the script can use, beyond the built-in Attack.
  def ability_slugs
    ai_script.map { |rule| rule["use"] }.uniq - [ "attack" ]
  end

  def abilities
    world.abilities.where(slug: ability_slugs).alphabetical
  end

  def drop_items
    world.items.where(slug: drops.map { |d| d["item"] }).index_by(&:slug)
  end

  # Cross-references (§7): the abilities that summon it, the encounter tables that roll it, the
  # location templates whose boss it is, and the NPCs and cast who fight as it.
  def summoned_by
    world.abilities.alphabetical.select { |a| Array(a.effects).any? { |e| e["primitive"] == "summon" && e["creature"] == slug } }
  end

  def rolled_by
    world.encounter_tables.alphabetical.select { |t| t.entries.any? { |e| e["monsters"].key?(slug) } }
  end

  def boss_of
    world.location_templates.alphabetical.select { |t| t.config.dig("boss", slug) }
  end

  def fought_as_by
    Npc.where(monster_id: id).order(:name).pluck(:name) + world.world_figures.where(monster_id: id).order(:name).pluck(:name)
  end

  def rewards
    { "exp" => exp, "gil" => gil, "abp" => abp }
  end

  # Enemy spec for Battle::State.build.
  def to_engine(count: 1, depth: 0)
    {
      "id" => slug,
      "name" => name,
      "count" => count,
      "stats" => stats,
      "types" => [ base_type ],
      "affinities" => affinities,
      "status_immune" => status_immune,
      "abilities" => ability_slugs,
      "ai" => ai_script,
      "rewards" => rewards,
      "drops" => (names = drop_items.transform_values(&:name); drops.map { |d| d.merge("name" => names[d["item"]]).compact }),
      "image" => { "book" => "monsters", "slug" => slug }
    }.merge(undead? ? { "undead" => true } : {}).merge(boss? ? { "boss" => true } : {}).merge(engine_phases(depth))
  end

  # Its phases as the engine takes them: each becomes the other entry's spec. A form's own
  # phases follow, to a depth (a chain of forms, not a loop).
  PHASE_DEPTH = 3

  def engine_phases(depth)
    return {} if phases.empty? || depth >= PHASE_DEPTH

    by_slug = world.monsters.where(slug: phases.map { |p| p["becomes"] }).index_by(&:slug)
    built = phases.filter_map do |phase|
      form = by_slug[phase["becomes"]] or next
      phase.merge("becomes" => form.to_engine(depth: depth + 1).except("count"))
    end
    built.any? ? { "phases" => built } : {}
  end

  private

  def stat_block_is_complete
    missing = Stats::NAMES - stats.keys
    errors.add(:stats, "is missing #{missing.join(', ')}") if missing.any?
    unknown = stats.keys - Stats::NAMES
    errors.add(:stats, "has unknown stats: #{unknown.join(', ')}") if unknown.any?
    bad = stats.reject { |name, v| JsonCasting.integer?(v) && v.between?(name == "max_hp" ? 1 : 0, Stats::CAPS.fetch(name, Float::INFINITY)) }
    errors.add(:stats, "must be whole numbers within caps (#{bad.keys.join(', ')})") if bad.any?
  end

  def affinities_are_affinities
    affinities.each do |type, affinity|
      errors.add(:affinities, "#{type} is not one of this world's types") unless world_types.include?(type)
      errors.add(:affinities, "#{affinity} is not an affinity") unless Battle::AFFINITIES.include?(affinity)
    end
  end

  def status_immunities_are_statuses
    unknown = status_immune - Battle::STATUSES
    errors.add(:status_immune, "has unknown statuses: #{unknown.join(', ')}") if unknown.any?
  end

  def still_needed
    return if destroyed_by_association # the whole world is going, books and all

    needs = []
    needs << "#{summoned_by.map(&:name).to_sentence} #{summoned_by.one? ? 'summons' : 'summon'} it" if summoned_by.any?
    needs << "#{rolled_by.map(&:name).to_sentence} #{rolled_by.one? ? 'rolls' : 'roll'} it" if rolled_by.any?
    needs << "it is the boss of #{boss_of.map(&:name).to_sentence}" if boss_of.any?
    needs << "#{fought_as_by.to_sentence} #{fought_as_by.one? ? 'fights' : 'fight'} as it" if fought_as_by.any?
    needs << "it is a form of #{form_of.map(&:name).to_sentence}" if form_of.any?
    return if needs.empty?

    errors.add(:base, "#{name} is still needed: #{needs.to_sentence}. Change those first.")
    throw :abort
  end

  def ai_script_is_valid
    known = world ? world.abilities.in_battle.where(slug: ability_slugs).pluck(:slug) : []
    field = world ? world.abilities.field.where(slug: ability_slugs).pluck(:slug) : []
    ai_script.each_with_index do |rule, i|
      label = "rule #{i + 1}"
      use = rule["use"]
      if field.include?(use)
        errors.add(:ai_script, "#{label} uses #{use}, a field ability, which can't be used in battle")
      elsif !(use == "attack" || known.include?(use))
        errors.add(:ai_script, "#{label} uses #{use}, which is not in the Grimoire")
      end
      if rule["target"] && !Battle::AI::STRATEGIES.include?(rule["target"])
        errors.add(:ai_script, "#{label} has unknown target #{rule['target']}")
      end
      errors.add(:ai_script, "#{label} says too much (200 letters at most)") if rule["say"].to_s.length > 200
      errors.add(:ai_script, "#{label} has unknown moment #{rule['when']}") if rule["when"] && !Battle::AI::TRIGGERS.include?(rule["when"])
      errors.add(:ai_script, "#{label} answers blows of #{rule['by']}, which isn't one of this world's types") if rule["by"] && !world_types.include?(rule["by"])
      rule.fetch("if", {}).each do |name, value|
        next errors.add(:ai_script, "#{label} has unknown condition #{name}") unless Battle::AI::CONDITIONS.include?(name)
        next if name == "ally_ko"

        next errors.add(:ai_script, "#{label} #{name} must be a positive whole number") unless JsonCasting.integer?(value) && value.positive?

        errors.add(:ai_script, "#{label} chance must be 1 to 100") if name == "chance" && value > 100
      end
    end
  end

  def phases_are_forms
    known = world ? world.monsters.where(slug: phases.map { |p| p["becomes"] }).pluck(:slug) : []
    phases.each_with_index do |phase, i|
      label = "phase #{i + 1}"
      errors.add(:phases, "#{label} becomes #{phase['becomes']}, which is not in the Bestiary") unless known.include?(phase["becomes"])
      errors.add(:phases, "#{label} can't become itself") if phase["becomes"] == slug
      errors.add(:phases, "#{label} HP below must be 1 to 99") unless phase["hp_below"].is_a?(Integer) && phase["hp_below"].between?(1, 99)
      errors.add(:phases, "#{label} restore must be 0 to 100") unless phase["restore"].between?(0, 100)
      errors.add(:phases, "#{label} says too much (200 letters at most)") if phase["say"].to_s.length > 200
    end
    errors.add(:phases, "must come in order, each below the last") unless phases.map { |p| p["hp_below"] }.compact.each_cons(2).all? { |a, b| b < a }
  end

  def drops_are_items
    known = world ? drop_items : {}
    drops.each do |drop|
      errors.add(:drops, "#{drop['item']} is not in the Armory") unless known.key?(drop["item"])
      chance = drop["chance"]
      errors.add(:drops, "#{drop['item']} chance must be 1–100") unless JsonCasting.integer?(chance) && chance.between?(1, 100)
    end
  end
end
