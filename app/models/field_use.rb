# frozen_string_literal: true

# A character's field ability, asked for at the table: their job's move
# outside battle (Job#field_ability). The player asks; the GM approves it at
# a difficulty, or vetoes it with a line. Approved, it's a check with the
# ability's skill (and the job's bonus) from the campaign's dice, and on a
# success the game applies the outcome. Once per rest, whatever the roll:
# a veto costs nothing.
class FieldUse < ApplicationRecord
  belongs_to :campaign
  belongs_to :character
  belongs_to :ability

  STATUSES = %w[pending done vetoed].freeze

  # What success does. Closed, like the battle primitives: a world names and
  # flavours them (Pick Lock, Hack Terminal, Commune with Spirits).
  OUTCOMES = {
    "story" => "The GM tells what happens",
    "reveal" => "Every place next to the party's comes into view",
    "sneak" => "The encounter waiting on the road is avoided",
    "find" => "An item worth up to its power in gil, into the bag",
    "restore" => "Everyone standing gets its power% of HP and MP back",
    "learn" => "The waiting encounter's weaknesses are known before the fight",
    "safe_road" => "The next dangerous path rolls no encounter",
    "uncover" => "One of the GM's secrets comes out, one about where the party is if there is one"
  }.freeze
  # What success does, with the ability's own numbers.
  def self.describe(ability)
    power = ability.field_power
    case ability.field_outcome
    when "find" then "An item worth up to #{power.positive? ? power : 100} #{ability.world.word('currency')}, into the bag"
    when "restore" then "Everyone standing gets #{power.positive? ? power : 25}% of #{ability.world.word('hp')} and #{ability.world.word('mp')} back"
    else OUTCOMES[ability.field_outcome]
    end
  end

  # These need an encounter on the road to act on.
  NEEDS_ENCOUNTER = %w[sneak learn].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :difficulty, inclusion: { in: Stats::Check::DIFFICULTIES.keys }, allow_nil: true

  scope :pending, -> { where(status: "pending") }

  after_commit :broadcast

  # The player (or the GM for them) asks. Raises Refusal with the
  # reason when it can't be asked for now.
  def self.request!(character)
    campaign = character.campaign
    ability = character.job.field_ability_entry or raise Refusal, "#{character.job.name} has no field ability"
    raise Refusal, "#{character.name} has used #{ability.name} since the last rest" if character.field_used?
    raise Refusal, "#{character.name} is down" unless character.conscious?
    raise Refusal, "Not while a battle is on" if campaign.battle_on?
    raise Refusal, "#{character.name} is already waiting on the GM" if campaign.field_uses.pending.exists?(character: character)
    raise Refusal, "There's no encounter on the road to #{ability.name.downcase} against" if NEEDS_ENCOUNTER.include?(ability.field_outcome) && !campaign.pending_encounter
    raise Refusal, "The party isn't on the map" if ability.field_outcome == "reveal" && !campaign.current_node

    transaction do
      use = campaign.field_uses.create!(character: character, ability: ability)
      campaign.narrate("#{character.name} wants to #{ability.name}.")
      use
    end
  end

  def pending?
    status == "pending"
  end

  def skill
    campaign.world.skill(ability.field_skill)
  end

  # The GM's yes: roll, and on a success, the outcome.
  def approve!(difficulty: ability.field_difficulty)
    raise Refusal, "Already settled" unless pending?
    raise Refusal, "Pick a difficulty" unless Stats::Check::DIFFICULTIES.key?(difficulty)

    transaction do
      campaign.lock!
      stat = skill ? skill["stat"] : "agi"
      bonus = character.skill_bonus(ability.field_skill)
      rolling = Battle::Rng.new(campaign.rng)
      roll = Stats::Check.roll(stat_value: character.stats.fetch(stat), stat: stat, level: character.level,
                               difficulty: difficulty, rng: rolling, bonus: bonus)
      campaign.update!(rng: rolling.state)
      label = "#{ability.name} (#{[ skill&.fetch('name'), difficulty, ("+#{bonus} #{character.job.name}" if bonus.positive?) ].compact.join(', ')})"
      campaign.narrate("#{character.name}: #{label}. #{roll['chance']}% · rolled #{roll['roll']} · #{roll['success'] ? 'Success!' : 'Failure.'}",
                       cue: "check", data: roll.merge("name" => character.name, "stat" => stat, "difficulty" => difficulty,
                                                      "skill" => skill&.fetch("name"), "bonus" => bonus).compact)
      line = roll["success"] ? apply_outcome : nil
      campaign.narrate(line) if line
      campaign.tick_clocks!("failed_check") unless roll["success"]
      character.update!(field_used: true)
      update!(status: "done", difficulty: difficulty, result: roll.merge("line" => line).compact)
    end
    campaign.broadcast_map if roll_revealed?
  end

  # The GM's no: nothing is spent.
  def veto!(line = nil)
    raise Refusal, "Already settled" unless pending?

    transaction do
      update!(status: "vetoed", result: { "line" => line.to_s.strip.presence }.compact)
      campaign.narrate("Not now, #{character.name}.#{" #{line.strip}" if line.present?}")
    end
  end

  private

  def roll_revealed?
    ability.field_outcome == "reveal" && result["success"]
  end

  # Applies the outcome; returns the line the table sees.
  def apply_outcome
    name = character.name
    case ability.field_outcome
    when "reveal" then reveal(name)
    when "sneak"
      return "The road was already clear." unless campaign.pending_encounter

      campaign.update!(pending_encounter: nil)
      "#{name} gets the party past without a fight."
    when "find" then find(name)
    when "restore" then restore(name)
    when "learn" then learn(name)
    when "safe_road"
      campaign.update!(safe_road: true)
      "#{name} finds a way through: the next dangerous path is safe."
    when "uncover"
      secret = Secret.next_for(campaign) or return "#{name} digs, but there's nothing more to find out."
      secret.reveal!(by: "#{name}'s #{ability.name}")
      nil
    else "#{name} manages it. What happens is the GM's to tell."
    end
  end

  def reveal(name)
    node = campaign.current_node or return "#{name} looks around, but there's no map to read."
    hidden = campaign.map_edges.select { |e| e.touches?(node) }.map { |e| e.other_end(node) }.reject(&:visible?)
    return "#{name} looks around: nothing new in sight." if hidden.empty?

    hidden.each { |n| n.update!(visible: true) }
    "#{name} scouts ahead: #{hidden.map(&:name).to_sentence} come#{'s' if hidden.one?} into view."
  end

  def find(name)
    worth = ability.field_power.positive? ? ability.field_power : 100
    finds = campaign.world.items.where(category: "consumable").where(price: 1..worth).order(:price, :id).to_a
    return "#{name} searches, but finds nothing worth the carrying." if finds.empty?

    rolling = Battle::Rng.new(campaign.rng)
    item = finds[rolling.int(finds.size)]
    campaign.update!(rng: rolling.state)
    campaign.add_item!(item)
    "#{name} finds #{item.name.start_with?(/[AEIOU]/i) ? 'an' : 'a'} #{item.name}."
  end

  def restore(name)
    share = ability.field_power.positive? ? ability.field_power : 25
    campaign.characters.select(&:conscious?).each do |c|
      c.update!(hp: [ c.current_hp + (c.stats["max_hp"] * share / 100), c.stats["max_hp"] ].min,
                mp: [ c.current_mp + (c.stats["max_mp"] * share / 100), c.stats["max_mp"] ].min)
    end
    "#{name} sees to everyone: #{share}% of #{campaign.world.word('hp')} and #{campaign.world.word('mp')} back."
  end

  def learn(name)
    monsters = campaign.world.monsters.where(slug: campaign.pending_encounter.to_h.fetch("monsters", {}).keys)
    return "There's nothing on the road to read." if monsters.empty?

    known = campaign.known_affinities.deep_dup
    engine = campaign.world.type_chart.to_engine
    monsters.each do |monster|
      notes = (known[monster.slug] ||= {})
      notes["types"] = [ monster.base_type ]
      Battle::Types.list(engine).each { |type| notes[type] = monster.affinities.fetch(type, "none") }
      Battle::STATUSES.each { |kind| notes[kind] = monster.status_immune.include?(kind) ? "immune" : "none" }
    end
    campaign.update!(known_affinities: known)
    "#{name} sizes up #{monsters.map(&:name).to_sentence}: their weaknesses are known."
  end

  # The GM's list of requests, and the player's own button.
  def broadcast
    broadcast_replace_to(campaign, :map_gm, target: "field_requests", partial: "campaigns/field_uses/requests", locals: { campaign: campaign })
    broadcast_replace_to(character, :whispers, target: "field_ability", partial: "campaigns/field_uses/ability", locals: { character: character.reload })
  end
end
