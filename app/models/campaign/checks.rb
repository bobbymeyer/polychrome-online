# frozen_string_literal: true

# Checks the GM calls for at the table; a failed one is an event (Campaign::Happenings).
module Campaign::Checks
  extend ActiveSupport::Concern

  # A check (Stats::Check): each character rolls against their own stat,
  # from the campaign's RNG, and the table sees it land. The GM calls for
  # one, or approves a player's field ability (FieldUse), which is a check
  # with an outcome. stat: a stat, or "skill:<slug>" for one of the world's
  # skills, rolled on its stat with each character's archetype bonus
  # (Character#skill_bonus). outcome: what a success makes happen (Outcome),
  # once, whoever succeeded; source: what did it, for a secret it brings out.
  # move: the name of what they tried, instead of the skill's ("Pick Lock").
  # Returns the check lines and the outcome's line.
  def check!(characters:, stat:, difficulty:, reason: nil, move: nil, outcome: nil, source: nil)
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
        label = "#{move || "#{skill ? skill['name'] : stat.capitalize} check"} (#{[ (skill['name'] if move && skill), difficulty,
                                                                          ("+#{bonus} #{character.job.name}" if bonus.positive?) ].compact.join(', ')})"
        body = "#{character.name}: #{label}#{" to #{reason.strip.sub(/\A(to\s+)+/i, '').sub(/\.\z/, '')}" if reason.present?}. " \
               "#{result['chance']}% · rolled #{result['roll']} · #{result['success'] ? 'Success!' : 'Failure.'}"
        [ body, result.merge("name" => character.name, "character_id" => character.id, "stat" => stat, "difficulty" => difficulty,
                             "skill" => skill&.fetch("name"), "bonus" => bonus, "move" => move,
                             "reason" => reason.to_s.strip.sub(/\.\z/, "").presence).compact ]
        end
      end
      created = lines.map { |body, data| narrate(body, cue: "check", data: data) }
      happen!("failed_check") if lines.any? { |_, data| !data["success"] }
      winner = lines.find { |_, data| data["success"] }&.last
      said = outcome && winner && outcome.apply!(self, by: winner["name"], source: source)
      narrate(said) if said
      [ created, said ]
    end
  end
end
