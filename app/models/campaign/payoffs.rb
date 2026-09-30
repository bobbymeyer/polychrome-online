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

    characters.includes(:job).order(:created_at).select(&:conscious?).filter_map do |character|
      payoff = character.job.payoff
      next if payoff.blank?

      [ character, payoff, payoff["kind"] == "rumour" ? 1 : payoff["amount"].to_i * parts ]
    end
  end

  # At a rest: everyone is paid, and the count starts again.
  def payday!
    owed = payoffs_owed
    update!(spent_parts: 0) if spent_parts.positive?
    owed.each do |character, payoff, amount|
      narrate(payoff_line(character, payoff, pay!(character, payoff["kind"], amount)))
    end
  end

  private

  # Pays one character. Returns what the line fills in: { amount:, rumour: }.
  def pay!(character, kind, amount)
    case kind
    when "money"
      increment!(:gil, amount)
      { amount: money(amount) }
    when "exp", "abp"
      gained = character.gain!(kind.to_sym => amount)
      grew = gained["level"] ? " Level #{gained['level'].last}!" : (gained["job_level"] ? " #{character.job.name} level #{gained['job_level'].last}!" : "")
      { amount: "#{amount} #{kind.upcase}", grew: grew }
    when "rumour"
      rumour = rumour_for_sale
      rumour&.update!(heard: true)
      hear_of!(rumour) if rumour
      { rumour: rumour && "“#{rumour.body}”" }
    end
  end

  DEFAULT_LINES = {
    "money" => "{who} earns {amount}.", "exp" => "{who} gets better at it: {amount}.",
    "abp" => "{who} practises: {amount}.", "rumour" => "{who} hears something: {rumour}"
  }.freeze

  def payoff_line(character, payoff, filled)
    line = payoff["line"].presence || DEFAULT_LINES.fetch(payoff["kind"])
    return "#{character.name} listens, but hears nothing new." if payoff["kind"] == "rumour" && filled[:rumour].nil?

    Generators::Lore.fill(line, who: character.name, amount: filled[:amount], rumour: filled[:rumour]) + filled[:grew].to_s
  end
end
