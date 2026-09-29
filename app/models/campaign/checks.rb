# frozen_string_literal: true

# Checks the GM calls for at the table, and the clocks that tick when they fail.
module Campaign::Checks
  extend ActiveSupport::Concern

  # The GM calls for a check (Stats::Check): each character rolls against
  # their own stat, from the campaign's RNG, and the table sees it land.
  # stat: a stat, or "skill:<slug>" for one of the world's skills, rolled
  # on its stat with each character's job bonus (Character#skill_bonus).
  def check!(characters:, stat:, difficulty:, reason: nil)
    skill = world.skill(stat.to_s.delete_prefix("skill:")) if stat.to_s.start_with?("skill:")
    stat = skill["stat"] if skill
    raise Refusal, "Pick who's trying" if characters.empty?
    raise Refusal, "Pick a skill or a stat" unless Stats::Check::STATS.include?(stat)
    raise Refusal, "Pick a difficulty" unless Stats::Check::DIFFICULTIES.key?(difficulty)

    transaction do
      lines = roll do |dice|
        characters.map do |character|
        bonus = skill ? character.skill_bonus(skill["slug"]) : 0
        result = Stats::Check.roll(stat_value: character.stats.fetch(stat), stat: stat, level: character.level,
                                   difficulty: difficulty, rng: dice, bonus: bonus)
        label = "#{skill ? skill['name'] : stat.capitalize} check (#{difficulty}#{", +#{bonus} #{character.job.name}" if bonus.positive?})"
        body = "#{character.name}: #{label}#{" to #{reason.strip.sub(/\.\z/, '')}" if reason.present?}. " \
               "#{result['chance']}% · rolled #{result['roll']} · #{result['success'] ? 'Success!' : 'Failure.'}"
        [ body, result.merge("name" => character.name, "character_id" => character.id, "stat" => stat, "difficulty" => difficulty,
                             "skill" => skill&.fetch("name"), "bonus" => bonus, "reason" => reason.to_s.strip.sub(/\.\z/, "").presence).compact ]
        end
      end
      created = lines.map { |body, data| narrate(body, cue: "check", data: data) }
      tick_clocks!("failed_check") if lines.any? { |_, data| !data["success"] }
      created
    end
  end

  # Every running clock that ticks on this (Clock::TRIGGERS) goes on a segment.
  def tick_clocks!(trigger)
    clocks.running.order(:id).select { |clock| clock.ticks_on?(trigger) }
          .each { |clock| clock.tick!(1, reason: Clock::REASONS[trigger]) }
  end
end
