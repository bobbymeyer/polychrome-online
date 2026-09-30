# frozen_string_literal: true

# Daily life pays off, through the party's archetypes (Job#payoff). Every
# part of the day the party spends on things to do (Campaign::Ways) is
# counted, and the next rest settles it: each character standing is paid
# their archetype's way (money for the party, EXP or ABP for them, per part
# of the day; or a rumour, once), and the table hears how.
module Campaign::Payoffs
  extend ActiveSupport::Concern

  # The most parts of the day one rest pays for.
  MOST_PARTS = 12

  def spent_time!(parts)
    increment!(:spent_parts, parts)
  end

  # What each character's archetype would pay for the time spent so far:
  # [[character, job, amount]].
  def payoffs_owed
    parts = spent_parts.clamp(0, MOST_PARTS)
    return [] if parts.zero?

    conscious_characters.filter_map do |character|
      payoff = character.job.payoff
      next if payoff.blank?

      [ character, payoff, payoff["kind"] == "rumour" ? 1 : payoff["amount"].to_i * parts ]
    end
  end

  # What each archetype pays, as the table reads it before the rest:
  # ["Rook, 40 gil a part", "Lenna, a rumour"].
  def payoff_preview
    conscious_characters.filter_map do |character|
      payoff = character.job.payoff.presence or next
      paid = case payoff["kind"]
      when "rumour" then "a rumour"
      when "money" then "#{money(payoff['amount'])} a part"
      else "#{payoff['amount']} #{payoff['kind'].upcase} a part"
      end
      "#{character.name}, #{paid}"
    end
  end

  # At a rest: everyone is paid, in the game's outcomes (Outcome), and the
  # count starts again.
  def payday!
    owed = payoffs_owed
    update!(spent_parts: 0) if spent_parts.positive?
    owed.each do |character, payoff, amount|
      line = payoff["line"].presence || DEFAULT_LINES.fetch(payoff["kind"])
      narrate(Outcome.of(payoff["kind"], amount).apply!(self, by: character.name, who: [ character ], line: line))
    end
  end

  DEFAULT_LINES = {
    "money" => "{who} earns {amount}.", "exp" => "{who} gets better at it: {amount}.",
    "abp" => "{who} practises: {amount}.", "rumour" => "{who} hears something: {rumour}"
  }.freeze
end
