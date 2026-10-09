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

  # What success can do: a share of the game's outcomes (Outcome), which a
  # world names and flavours (Pick Lock, Hack Terminal, Commune with Spirits).
  OUTCOMES = Outcome::KINDS.slice(*%w[story reveal sneak find restore learn safe_road uncover unlock]).transform_values(&:first).freeze

  # The ability's outcome, with its own numbers (none: the outcome's own).
  def self.outcome_of(ability)
    Outcome.of(ability.field_outcome, (ability.field_power if ability.field_power.to_i.positive?))
  end

  # What success does, with the ability's own numbers.
  def self.describe(ability) = outcome_of(ability).describe(ability.world)

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
    raise Refusal, "#{character.name} is KO'd" unless character.conscious?
    raise Refusal, "Not while a battle is on" if campaign.battle_on?
    raise Refusal, "#{character.name} is already waiting on the GM" if campaign.field_uses.pending.exists?(character: character)
    outcome_of(ability).can_happen!(campaign)

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

  # The GM's yes: a check with the ability's skill (Campaign#check!), and
  # on a success, the outcome.
  def approve!(difficulty: ability.field_difficulty)
    raise Refusal, "Already settled" unless pending?

    transaction do
      campaign.lock!
      stat = skill ? "skill:#{skill['slug']}" : "agi"
      checked, line = campaign.check!(characters: [ character ], stat: stat, difficulty: difficulty, move: ability.name,
                                      outcome: self.class.outcome_of(ability), source: "#{character.name}'s #{ability.name}")
      character.update!(field_used: true)
      update!(status: "done", difficulty: difficulty, result: checked.sole.data.merge("line" => line).compact)
    end
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

  # The GM's list of requests, and the player's own button.
  def broadcast
    broadcast_replace_to(campaign, :gm, target: "field_requests", partial: "campaigns/field_uses/requests", locals: { campaign: campaign })
    broadcast_replace_to(character, :whispers, target: "field_ability", partial: "campaigns/field_uses/ability", locals: { character: character.reload })
  end
end
