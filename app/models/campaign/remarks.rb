# frozen_string_literal: true

# Lines the world offers the GM, matched to the moment (docs/STORY.md,
# items 6 and 7). The world's story tables go through the story matcher
# (Story::Matcher) with the moment's facts (Campaign::Moment) and the
# table's lines and veils; the row that fits best comes to the GM as a
# note, to say or to skip. Nothing is said for the GM: said, the line goes
# to the table in the narrator's voice, and what the row remembers is
# written to the campaign's flags, so later rows can ask about it.
#
#   arrivals       on each arrival, the line that fits the place best
#   complications  on a failed check, the GM's moves (Dungeon World's, ch.
#                  20): the best soft one, words only (show signs, an
#                  unwelcome truth, an opportunity), and the best hard one,
#                  which takes something too (an Outcome::TAKES: hurt,
#                  weary, lose, time, tick, ambush)
module Campaign::Remarks
  extend ActiveSupport::Concern

  # What a complication's row can ask about besides the moment: the check
  # that failed. key (as written) => what it is.
  CHECK_FACTS = {
    "check" => "True: a check just failed.",
    "who" => "Who failed it, by name (Rook, or Rook and Vivi).",
    "failed, succeeded" => "How many failed it, and how many made it.",
    "stat" => "The stat it was on: str, mag, vit, spr or agi.",
    "skill" => "The skill, if it was one, as a key (stealth); that key is true too.",
    "move" => "What they tried, for a field ability (pick_lock); that key is true too.",
    "difficulty" => "easy, normal, hard or heroic; that word is true too."
  }.freeze

  # Offers the best-fitting arrival line for a place, if any row fits.
  # Returns the note, or nil.
  def offer_arrival_line!(node)
    rows = story_rows("arrivals")
    return nil if rows.empty?

    _, line = Story::Matcher.best(rows, moment(at: node), story_dice(node), avoid: every_line + every_veil)
    return nil unless line

    narrate("To say, arriving at #{node.name}: “#{line['text']}”", scope: "gm",
            data: { "offer" => line.slice("text", "sets") })
  end

  # A check failed (Campaign#check!): the GM is offered a soft move and a
  # hard one, each the row that fits best, to make or to let go by.
  # results: the check's lines' data. Returns the notes.
  def offer_complications!(results)
    rows = story_rows("complications")
    return [] if rows.empty? || results.all? { |result| result["success"] }

    facts = moment.merge(check_facts(results))
    soft, hard = rows.partition { |row| row["does"].blank? }
    hard = hard.select { |row| (outcome = Outcome.parse(row["does"])) && outcome.bites?(self) }
    state = Battle::Rng.seed_state(rng ^ 0x9E37_79B9)
    [ [ soft, "A soft move" ], [ hard, "A hard move" ] ].filter_map do |candidates, label|
      state, line = Story::Matcher.best(candidates, facts, state, avoid: every_line + every_veil)
      next unless line

      does = line["row"]["does"].presence
      takes = Outcome.parse(does)&.describe(world) if does
      narrate("#{label}, for the failed check: “#{line['text']}”#{" (#{takes})" if takes}", scope: "gm",
              data: { "offer" => line.slice("text", "sets").merge("does" => does).compact })
    end
  end

  # The GM says an offered line: it goes to the table, what its row
  # remembers is remembered, and a hard move's outcome happens.
  def say_offer!(note)
    offer = note.data.to_h["offer"]
    raise Refusal, "That isn't a line to say." unless note.campaign_id == id && note.gm_only? && offer
    raise Refusal, "Already said." if note.data["said"]

    outcome = Outcome.parse(offer["does"]) if offer["does"]
    outcome&.can_happen!(self)
    transaction do
      messages.create!(kind: "say", body: offer["text"])
      Array(offer["sets"]).each { |write| remember_fact!(write) }
      if outcome && (said = outcome.apply!(self, by: "The party"))
        narrate(said)
      end
      note.update!(data: note.data.merge("said" => true))
    end
  end

  private

  def story_rows(kind)
    world.generator_tables.where(kind: kind).order(:id).flat_map(&:entries)
  end

  # Dice of their own for each arrival, from the campaign's and the place
  # and the visit, so a line offered never moves the dice a fight rolls with.
  def story_dice(node)
    Battle::Rng.seed_state(rng ^ (node.id * 2_654_435_761) ^ (visits_to(node) * 40_503))
  end

  def check_facts(results)
    failed = results.reject { |result| result["success"] }
    first = results.first
    facts = { "check" => true, "who" => failed.map { |r| r["name"] }.to_sentence, "failed" => failed.size,
              "succeeded" => results.size - failed.size, "stat" => first["stat"], "difficulty" => first["difficulty"] }
    facts[first["difficulty"]] = true if first["difficulty"]
    { "skill" => first["skill"], "move" => first["move"] }.each do |what, name|
      next if name.blank?

      facts[what] = Campaign::Moment.key(name)
      facts[Campaign::Moment.key(name)] = true
    end
    facts.compact
  end

  def remember_fact!(write)
    flag = flags.find_or_initialize_by(key: write["key"])
    flag.update!(value: Story::Criteria.written(write, flag.value))
  end
end
