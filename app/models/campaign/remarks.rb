# frozen_string_literal: true

# Lines the world offers the GM, matched to the moment (docs/STORY.md,
# item 6). On each arrival, the world's arrivals tables go through the story
# matcher (Story::Matcher) with the moment's facts (Campaign::Moment) and
# the table's lines and veils; the row that fits best comes to the GM as a
# note, to say or to skip. Nothing is said for the GM: said, the line goes
# to the table in the narrator's voice, and what the row remembers is
# written to the campaign's flags, so later rows can ask about it.
module Campaign::Remarks
  extend ActiveSupport::Concern

  # Offers the best-fitting arrival line for a place, if any row fits.
  # Returns the note, or nil.
  def offer_arrival_line!(node)
    rows = world.generator_tables.where(kind: "arrivals").order(:id).flat_map(&:entries)
    return nil if rows.empty?

    facts = moment(at: node)
    _, line = Story::Matcher.best(rows, facts, story_dice(node), avoid: every_line + every_veil)
    return nil unless line

    narrate("To say, arriving at #{node.name}: “#{line['text']}”", scope: "gm",
            data: { "offer" => line.slice("text", "sets") })
  end

  # The GM says an offered line: it goes to the table, and what its row
  # remembers is remembered.
  def say_offer!(note)
    offer = note.data.to_h["offer"]
    raise Refusal, "That isn't a line to say." unless note.campaign_id == id && note.gm_only? && offer
    raise Refusal, "Already said." if note.data["said"]

    transaction do
      messages.create!(kind: "say", body: offer["text"])
      Array(offer["sets"]).each { |write| remember_fact!(write) }
      note.update!(data: note.data.merge("said" => true))
    end
  end

  private

  # Dice of their own for each arrival, from the campaign's and the place
  # and the visit, so a line offered never moves the dice a fight rolls with.
  def story_dice(node)
    Battle::Rng.seed_state(rng ^ (node.id * 2_654_435_761) ^ (visits_to(node) * 40_503))
  end

  def remember_fact!(write)
    flag = flags.find_or_initialize_by(key: write["key"])
    flag.update!(value: Story::Criteria.written(write, flag.value))
  end
end
