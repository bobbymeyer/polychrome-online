# frozen_string_literal: true

# "Previously on…": what happened last session, for a table coming back
# after a break. Built from the table's own record: the log, the battles,
# the flags and secrets the party knows and the clocks that filled. Whispers are never in it.
#
# A session is a run of log lines with no gap longer than BREAK. The recap
# is of the last session that has ended; while the first session is still
# going, it is of that one.
class Recap
  BREAK = 3.hours

  PLACE_LINES = [
    /\AThe party travels from .+ to (?<place>.+)\.\z/,
    /\AThe party is at (?<place>.+)\.\z/,
    /\A(?<place>[^:]+): the party enters /
  ].freeze

  attr_reader :campaign, :window

  def self.for(campaign, now: Time.current)
    times = campaign.messages.where(scope: "table").order(created_at: :desc).pluck(:created_at)
    return if times.empty?

    sessions = times.slice_when { |later, earlier| later - earlier > BREAK }.map { |run| run.last..run.first }
    ended = sessions.find { |s| s.end < now - BREAK }
    new(campaign, ended || sessions.first, ended: !ended.nil?)
  end

  def initialize(campaign, window, ended: true)
    @campaign = campaign
    @window = window
    @ended = ended
  end

  # Of a session that's over (not the one being played): worth opening by
  # itself for someone arriving. The one still going is only a link away.
  def ended? = @ended

  def lines
    @lines ||= campaign.messages.where(scope: "table", created_at: window).chronological.to_a
  end

  # Where the party went, in order, without repeats.
  def places
    lines.select(&:system?).filter_map { |m| PLACE_LINES.lazy.filter_map { |re| re.match(m.body)&.[](:place) }.first }.uniq
  end

  def battles
    @battles ||= campaign.battles.where(created_at: window).where.not(status: %w[input abandoned]).order(:created_at).to_a
  end

  # "Won against the Goblin Chief", from each battle's settlement.
  def battle_lines
    battles.map do |battle|
      result = { "victory" => "Won", "defeat" => "Lost", "fled" => "Fled" }.fetch(battle.status, battle.status.humanize)
      fates = Array(battle.settlement&.dig("antagonists")).filter_map do |a|
        { "escaped" => "#{a['name']} got away", "slipped_away" => "#{a['name']} slipped away", "defeated" => "#{a['name']} fell" }[a["fate"]]
      end
      fates = battle.boss_monsters.map { |m| "#{m.name} fell" } if fates.empty? && battle.status == "victory"
      "#{result}: #{battle.name}#{" (#{fates.to_sentence})" if fates.any?}"
    end
  end

  def level_ups
    battles.flat_map do |battle|
      Array(battle.settlement&.dig("members")).filter_map do |member|
        "#{member['name']} reached level #{member['level'].last}" if member["level"]
      end
    end
  end

  def found
    lines.select { |m| %w[key treasure].include?(m.cue) }.map(&:body)
  end

  # Public flags set, secrets found out, and clocks that filled.
  def learned
    campaign.flags.shown_to_players.where(updated_at: window).order(:key).map { |f| f.value.present? ? "#{f.label}: #{f.value}" : f.label } +
      campaign.secrets.where(revealed_at: window).order(:revealed_at).map(&:body) +
      campaign.clocks.shown_to_players.where(full_at: window).order(:full_at).map { |c| "#{c.name}: it happened" }
  end

  # The last thing said to the table: where it was left.
  def last_line
    lines.reverse.find(&:dialogue?)
  end

  def here
    campaign.current_node&.name
  end

  def ended_at
    window.end
  end

  # Where the story had got to when it ended: "Moonsday, 12 Rainfall", or nil
  # for a session from before the log kept story time.
  def ended_on
    day = lines.reverse.find(&:day)&.day
    campaign.world.date(day) if day
  end

  def empty?
    places.empty? && battle_lines.empty? && found.empty? && learned.empty? && last_line.nil?
  end
end
