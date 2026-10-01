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
#   signs          on each arrival, maybe a sign of a clock's latest step
#                  (Portent), more likely the fuller the clock (item 8)
#   complications  on a failed check, the GM's moves (Dungeon World's, ch.
#                  20): the best soft one, words only (show signs, an
#                  unwelcome truth, an opportunity), and the best hard one,
#                  which takes something too (an Outcome::TAKES: hurt,
#                  weary, lose, time, tick, ambush)
#   clues          on arriving where a secret is, or when its person speaks,
#                  the next of its clues (Secret#find_clue!; item 11)
#   events         on a rest or a journey (one without a fight), what
#                  happens at camp or on the road, with a choice for the
#                  table whose options do what they say (EventChoices; item 10)
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

  # Maybe a sign of trouble coming, on arriving somewhere: each running
  # clock with steps written, fullest first, has its share filled as the
  # chance (a clock 3 of 6 along, half the time); the first that comes up
  # offers the sign of its latest step that fits the moment best, or an
  # earlier step's. At most one a visit. Returns the note, or nil.
  def offer_sign!(node)
    candidates = clocks.running.where.not(portents: nil).where("filled > 0").to_a
                       .sort_by { |clock| [ -clock.filled.fdiv(clock.segments), clock.id ] }
    return nil if candidates.empty?

    facts = moment(at: node)
    dice = Battle::Rng.new(story_dice(node) ^ 0x5BD1_E995)
    candidates.each do |clock|
      next unless dice.percent?(100 * clock.filled / clock.segments)

      clock.reached_portents.each do |portent, _segment|
        _, line = Story::Matcher.best(portent.signs, facts, dice.state, avoid: every_line + every_veil)
        next unless line

        return narrate("A sign of “#{clock.name}” (#{clock.filled} of #{clock.segments}): “#{line['text']}”", scope: "gm",
                       data: { "offer" => line.slice("text", "sets") })
      end
    end
    nil
  end

  # The next clue of a secret about a place the party arrives at (or about
  # someone who lives there), for the GM to let them find. One a visit.
  def offer_clue_at!(node)
    location = node.location or return nil
    chained = secrets.kept.where.not(steps: nil)
    secret = chained.where(location: location).or(chained.where(npc: npcs.where(location: location))).order(:id).find(&:next_clue)
    offer_clue!(secret, at: "at #{node.name}", by: "In #{node.name}") if secret
  end

  # The next clue of a secret about someone who just spoke at the table.
  def offer_clue_from!(npc)
    secret = secrets.kept.where.not(steps: nil).where(npc: npc).order(:id).find(&:next_clue)
    offer_clue!(secret, at: "from #{npc.name}", by: npc.name) if secret
  end

  # Where an event happens, as facts a row can ask about.
  EVENT_FACTS = {
    "rest, camp, inn" => "On a rest: true; camp when it's not a bed, inn when it is.",
    "road, journey" => "On a journey: true.",
    "to" => "On a journey: where the party is going."
  }.freeze

  # Something happens at camp or on the road (Campaign#happen!): the event
  # that fits best, with the options the party could take now, is offered
  # to the GM to put to the table. on: "rest" (bed: whether it's a bed) or
  # "travel". A journey with a fight on it has had its event. Returns the
  # note, or nil.
  def offer_event!(on, bed: false)
    return nil if on == "travel" && pending_encounter

    rows = story_rows("events")
    return nil if rows.empty?

    facts = on == "rest" ? moment.merge("rest" => true, (bed ? "inn" : "camp") => true) : moment(at: nil).merge("road" => true, "journey" => true, "to" => current_node&.name)
    choosable = rows.filter_map do |row|
      choices, problems = EventChoices.parse(row["choices"])
      next row if choices.nil?
      next if problems.any?

      options = choices.possible(self)
      row.merge("choices" => EventChoices.new(options: options, flag: choices.flag)) if options.size >= 2
    end
    state = Battle::Rng.seed_state(rng ^ (parts_gone * 2_246_822_519) ^ (on == "rest" ? 1 : 2))
    _, line = Story::Matcher.best(choosable, facts.compact, state, avoid: every_line + every_veil)
    return nil unless line

    choices = line["row"]["choices"]
    offer = line.slice("text", "sets")
    offer = offer.merge("choices" => choices.options, "flag" => choices.flag).compact if choices
    where = on == "rest" ? (bed ? "at the inn" : "at camp") : "on the road"
    said = choices ? " #{choices.options.map { |o| [ o['label'], (o['does'].map { |w| Outcome.parse(w).describe(world).downcase_first }.join(', ').presence) ].compact.join(': ') }.join(' · ')}" : ""
    narrate("An event, #{where}: “#{line['text']}”#{said}", scope: "gm", data: { "offer" => offer })
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
  # remembers is remembered, and a hard move's outcome happens. An offered
  # clue is found, if it's still the next one.
  def say_offer!(note)
    offer = note.data.to_h["offer"]
    raise Refusal, "That isn't a line to say." unless note.campaign_id == id && note.gm_only? && offer
    raise Refusal, "Already said." if note.data["said"]
    return let_them_find!(note, offer) if offer["clue"]

    transaction do
      say_line!(offer["text"], sets: offer["sets"], does: offer["does"])
      put_to_the_table!(offer["choices"], flag: offer["flag"]) if offer["choices"]
      note.update!(data: note.data.merge("said" => true))
    end
  end

  private

  # Rows of a kind from every one of the world's tables of it.
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

  # A clue offered once at a time for each step: none while one is waiting.
  def offer_clue!(secret, at:, by:)
    clue = secret.next_clue or return nil
    waiting = messages.where(scope: "gm").where("json_extract(data, '$.offer.clue') = ? AND json_extract(data, '$.offer.step') = ?", secret.id, secret.found)
                      .where("json_extract(data, '$.said') IS NULL")
    return nil if waiting.exists?

    said = secret.found.zero? ? "A question #{at}: #{clue}" : "A clue #{at}, toward “#{secret.question}”: #{clue}"
    narrate(said, scope: "gm",
            data: { "offer" => { "clue" => secret.id, "step" => secret.found, "text" => clue.to_s, "by" => by } })
  end

  def let_them_find!(note, offer)
    secret = secrets.find_by(id: offer["clue"])
    raise Refusal, "The party has found that one already." if secret.nil? || secret.revealed? || secret.found != offer["step"]

    transaction do
      secret.find_clue!(by: offer["by"])
      note.update!(data: note.data.merge("said" => true))
    end
  end

  # An event's choice, for the party to pick and the GM to settle: the
  # option settled on does what it says (Message::Choice#settle!).
  def put_to_the_table!(options, flag: nil)
    raise Refusal, "Settle the choice the table has open first." if open_choice

    choice = Message.choice(self, options: options.map { |o| o["label"] }, flag: flag)
    choice.data = { "outcomes" => options.to_h { |o| [ o["label"], o["does"] ] } }
    choice.save!
  end

  def remember_fact!(write)
    flag = flags.find_or_initialize_by(key: write["key"])
    flag.update!(value: Story::Criteria.written(write, flag.value))
  end
end
