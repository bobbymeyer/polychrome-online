# frozen_string_literal: true

# What a campaign's legends page tells (LegendsController): the world's
# written history (Chronicle), the parts that touch places the party knows,
# and the party's own story by day: their deeds, the rumours they heard,
# and the secrets they uncovered. With gm: true, all of the history, with
# what really happened.
class Legends
  Entry = Data.define(:day, :kind, :text, :where)

  attr_reader :campaign

  def initialize(campaign, gm: false)
    @campaign = campaign
    @gm = gm
  end

  def gm? = @gm

  # [{ "ago", "text", "truth", "known" }], oldest first.
  def history
    known = campaign.map_nodes.where(visible: true).where.not(world_place_id: nil).pluck(:world_place_id).to_set
    Chronicle.new(campaign.world).written_events.filter_map do |event|
      places = Array(event["places"]).map { |key| Chronicle.place_id(key) }
      told = places.empty? || places.any? { |id| known.include?(id) }
      next unless told || gm?

      { "ago" => event["ago"], "text" => event["text"], "truth" => (event["truth"] if gm?), "known" => told }
    end
  end

  # The party's story, by day: deeds, rumours heard, the fights they saw
  # through (as the table heard each end), and what they chose together
  # (not where to go: that's the road, not the story).
  def story
    names = campaign.map_nodes.pluck(:id, :name).to_h
    deeds = campaign.deeds.in_order.map { |d| Entry.new(day: d.day, kind: "deed", text: d.body, where: names[d.origin_id]) }
    heard = campaign.rumours.talk.where(heard: true).where.not(heard_day: nil).order(:heard_day, :id)
                    .map { |r| Entry.new(day: r.heard_day, kind: "rumour", text: r.body, where: names[r.heard_at_id]) }
    (deeds + heard + fights + choices).sort_by(&:day).group_by(&:day)
  end

  def fights
    over = campaign.battles.where(status: %w[victory defeat fled]).select(:id)
    campaign.messages.where(battle_id: over).where.not(day: nil).order(:id).group_by(&:battle_id)
            .map { |_, said| said.last }.map { |line| Entry.new(day: line.day, kind: "battle", text: line.body, where: nil) }
  end

  def choices
    campaign.messages.where(kind: "choice").where.not(settled: nil).where.not(day: nil).order(:id)
            .reject { |choice| choice.where_next? }.map { |choice| Entry.new(day: choice.day, kind: "choice", text: "Chose: #{choice.settled}.", where: nil) }
  end

  def uncovered
    campaign.secrets.revealed.order(:revealed_at)
  end

  def empty? = history.empty? && story.empty? && uncovered.empty?
end
