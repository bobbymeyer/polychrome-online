# frozen_string_literal: true

# A tiered set of Grimoire entries written from one form: name a root and
# a type, pick a shape, and it writes the four tiers (Fire, Fira, Firaga,
# Firaja), and puts them in a job's learn table if asked. Each one is an
# ordinary entry afterwards, to be tweaked on its own.
class AbilityFamily
  include ActiveModel::Model

  Tier = Data.define(:target, :power, :mp, :level)

  # [kind, primitive, tiers]: one foe, one foe harder, all foes, all foes harder.
  SHAPES = {
    "caster" => [ "magic", "elemental", [ Tier.new("single_enemy", 12, 4, 1), Tier.new("single_enemy", 26, 10, 20),
                                         Tier.new("all_enemies", 14, 14, 40), Tier.new("all_enemies", 28, 26, 60) ] ],
    "striker" => [ "skill", "physical", [ Tier.new("single_enemy", 130, 3, 1), Tier.new("single_enemy", 200, 8, 20),
                                         Tier.new("all_enemies", 90, 12, 40), Tier.new("all_enemies", 150, 22, 60) ] ],
    "healer" => [ "magic", "heal", [ Tier.new("single_ally", 25, 4, 1), Tier.new("single_ally", 60, 10, 20),
                                    Tier.new("all_allies", 20, 12, 40), Tier.new("all_allies", 45, 24, 60) ] ],
    # Power is the chance of the status landing.
    "hexer" => [ "magic", "status", [ Tier.new("single_enemy", 60, 3, 1), Tier.new("single_enemy", 90, 8, 20),
                                     Tier.new("all_enemies", 50, 12, 40), Tier.new("all_enemies", 80, 22, 60) ] ]
  }.freeze
  SHAPE_LABELS = { "caster" => "Caster: damage of a type", "striker" => "Striker: blows of a type",
                   "healer" => "Healer: restore HP", "hexer" => "Hexer: inflict a status" }.freeze
  GESTURES = { "caster" => "flash", "striker" => "lunge", "healer" => "float", "hexer" => "tint" }.freeze

  attr_accessor :world, :root, :shape, :type, :status, :job_id, :tiers

  validates :root, presence: true
  validates :shape, inclusion: { in: SHAPES.keys }
  validate :type_or_status_fits

  # Fire → Fire, Fira, Firaga, Firaja: a trailing vowel gives way.
  def self.names_for(root)
    stem = root.to_s.strip.sub(/[aeiou]\z/i, "")
    [ root.to_s.strip, "#{stem}a", "#{stem}aga", "#{stem}aja" ]
  end

  def kind = SHAPES.fetch(shape)[0]
  def primitive = SHAPES.fetch(shape)[1]
  def presets = SHAPES.fetch(shape)[2]

  # The posted tiers over the shape's presets: name, power, mp, level.
  def rows
    names = self.class.names_for(root)
    presets.each_with_index.map do |preset, i|
      posted = Array(tiers)[i].to_h
      { "name" => posted["name"].presence || names[i], "description" => posted["description"].presence, "target" => preset.target,
        "power" => (posted["power"].presence || preset.power).to_i, "mp" => (posted["mp"].presence || preset.mp).to_i,
        "level" => (posted["level"].presence || preset.level).to_i }
    end
  end

  def job
    world.jobs.find_by(id: job_id) if job_id.present?
  end

  # Writes the entries (and learn-table rows). Returns them, or false with
  # errors set; nothing is written unless all of it is.
  def save
    return false unless valid?

    written = []
    ActiveRecord::Base.transaction do
      rows.each do |row|
        ability = world.abilities.new(name: row["name"], kind: kind, target: row["target"], mp_cost: row["mp"],
                                      gesture: GESTURES[shape], effects: [ effect(row) ],
                                      description: row["description"] || "#{root.strip}, #{tier_word(written.size)}.")
        unless ability.save
          ability.errors.full_messages.each { |m| errors.add(:base, "#{row['name']}: #{m}") }
          raise ActiveRecord::Rollback
        end
        job&.job_levels&.create!(level: row["level"].clamp(1, Stats::Growth::MAX_JOB_LEVEL), ability: ability)
        written << ability
      end
    end
    errors.empty? && written
  end

  private

  def effect(row)
    case primitive
    when "elemental" then { "primitive" => "elemental", "type" => type, "power" => row["power"] }
    when "physical" then { "primitive" => "physical", "type" => type.presence, "power" => row["power"] }.compact
    when "heal" then { "primitive" => "heal", "power" => row["power"] }
    when "status" then { "primitive" => "status", "kind" => status, "chance" => row["power"].clamp(1, 100), "duration" => 3 }
    end
  end

  def tier_word(index)
    [ "the first step", "stronger", "spread across every target", "at its strongest across every target" ][index]
  end

  def type_or_status_fits
    return unless SHAPES.key?(shape)

    if primitive == "elemental" && !world.type_chart.include?(type)
      errors.add(:type, "must be one of #{world.name}'s types")
    elsif primitive == "physical" && type.present? && !world.type_chart.include?(type)
      errors.add(:type, "must be one of #{world.name}'s types")
    elsif primitive == "status" && (Battle::HARMFUL_STATUSES - Battle::PRIMITIVE_STATUSES).exclude?(status)
      errors.add(:status, "must be a status to inflict")
    end
  end
end
