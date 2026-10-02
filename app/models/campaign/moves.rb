# frozen_string_literal: true

# What's live, for the GM's moves panel (docs/STORY.md, item 9; Dungeon
# World's GM moves, ch. 20): when the table stalls, the moves the game can
# see, for the GM to make one or ignore them all. It reads what's there:
#
#   soft, hard     the complications that fit the moment best (Remarks)
#   dangers        each running clock with something to say: what it wants,
#                  its next step, and a sign of where it has got to
#   wants          wishes the party has heard and not met: an item someone
#                  wants brought, or the nearest dungeon cleared
#   got away       antagonists who got away, and where they are
#   chains         secrets coming out a clue at a time: the next clue
#
# Nothing here happens by itself: the GM says a line (#say_line!), ticks a
# clock, or lets it all go by.
module Campaign::Moves
  extend ActiveSupport::Concern

  Danger = Data.define(:clock, :sign)
  Want = Data.define(:who, :place, :wish, :wants)

  # The soft move and the hard move that fit the moment best, either nil:
  # { "soft" => line, "hard" => line } (Story::Matcher's lines).
  def moves_now
    rows = story_rows("complications")
    soft, hard = rows.partition { |row| row["does"].blank? }
    hard = hard.select { |row| (outcome = Outcome.parse(row["does"])) && outcome.bites?(self) }
    facts = moment
    state = Battle::Rng.seed_state(rng ^ 0x2545_F491)
    { "soft" => soft, "hard" => hard }.transform_values do |candidates|
      state, line = Story::Matcher.best(candidates, facts, state, avoid: every_line + every_veil)
      line
    end
  end

  # Running clocks with something to say, fullest first.
  def dangers
    facts = moment
    clocks.running.order(:id).to_a.select { |clock| clock.impulse || clock.portents }
          .sort_by { |clock| [ -clock.filled.fdiv(clock.segments), clock.id ] }.map do |clock|
      sign = clock.reached_portents.lazy.filter_map do |portent, _|
        Story::Matcher.best(portent.signs, facts, Battle::Rng.seed_state(rng ^ clock.id), avoid: every_line + every_veil).last
      end.first
      Danger.new(clock: clock, sign: sign)
    end
  end

  # Wishes heard in towns the party has been to, not met yet, that the
  # party could meet: an item brought, or a dungeon cleared.
  def wants_heard
    items = world.items.index_by(&:slug)
    map_nodes.where(kind: "town").includes(:location).order(:name).select { |node| node.location && visits_to(node).positive? }.flat_map do |node|
      town = node.location
      town.townsfolk.filter_map do |person|
        next if person["wish"].blank? || town.met?(person["key"])

        wants = items[person["wants"]]&.name || (town.fill_in("{dungeon}") if person["wish"].include?("{dungeon}"))
        Want.new(who: person["name"], place: node.name, wish: town.fill_in(person["wish"]), wants: wants) if wants
      end
    end
  end

  # Secrets coming out a step at a time with a clue still to find.
  def chains = secrets.kept.where.not(steps: nil).includes(:npc, location: :map_node).order(:id).select(&:next_clue)

  # Antagonists who have got away at least once, and are still out there.
  def got_away = npcs.at_large.where("escapes > 0").includes({ location: :map_node }, :monster).order(:name)

  # The GM makes a line from the panel (or an offered one) so: it goes to
  # the table in the narrator's voice, what its row remembers is
  # remembered, and a hard move's outcome happens. sets: write hashes
  # (Story::Criteria); does: what it takes (Outcome::TAKES), or nil.
  def say_line!(text, sets: [], does: nil)
    outcome = Outcome.parse(does) if does.present?
    raise Refusal, "“#{does}” isn't something a hard move takes" if does.present? && !Outcome::TAKES.include?(outcome&.kind)
    raise Refusal, "Say what happens." if text.to_s.strip.empty?

    outcome&.can_happen!(self)
    transaction do
      messages.create!(kind: "say", body: text)
      Array(sets).each { |write| remember_fact!(write) }
      if outcome && (said = outcome.apply!(self, by: "The party"))
        narrate(said)
      end
    end
  end
end
