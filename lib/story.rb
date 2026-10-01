# frozen_string_literal: true

require_relative "battle"
require_relative "generators/pool"
require_relative "story/criteria"
require_relative "story/words"
require_relative "story/matcher"

# The story matcher (docs/STORY.md, item 6; Ruskin's rule system for Left 4
# Dead, ch. 25 of Procedural Storytelling in Game Design). Pure, like the
# resolver: facts about the moment go in, as a flat hash; each row says
# when it fits; every row that fits competes, the most specific wins, and
# ties go to the seeded RNG. A row can also say what to remember, written
# back to the campaign's flags by whoever uses it.
#
#   Story::Matcher.best(rows, facts, rng_state, avoid: lines_and_veils)
#     # => [next_rng_state, { "text", "sets", "score", "row" } or nil]
module Story
end
