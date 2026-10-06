# frozen_string_literal: true

# Lines and veils for one table, beside its world's (docs/STORY.md, item 5;
# the "Lines and veils" of ch. 5). Anyone at the table can draw one, from
# any seat, and nothing records who: the table hears that it was drawn, not
# by whom. Only the GM takes one off, on the campaign's edit page.
#
# A line never happens; a veil happens off-screen. The language model is
# told both, the world's and the table's (Drafts::Base#voice).
module Campaign::Limits
  extend ActiveSupport::Concern

  KINDS = { "line" => :lines, "veil" => :veils }.freeze
  MAX_LENGTH = 120
  SAID = { "line" => "never", "veil" => "off-screen" }.freeze

  # Every line, the world's then the table's, one each.
  def every_line = (world.line_list(:lines) + line_list(:lines)).uniq
  def every_veil = (world.line_list(:veils) + line_list(:veils)).uniq

  # Adds a line ("line") or a veil ("veil") to this table's and tells the
  # table, with no name on it. Adding one already there changes nothing.
  def draw_limit!(kind, text)
    column = KINDS.fetch(kind.to_s) { raise Refusal, "A line or a veil, nothing else." }
    text = text.to_s.squish
    raise Refusal, "Say what it is." if text.empty?
    raise Refusal, "Keep it short: #{MAX_LENGTH} characters at most." if text.length > MAX_LENGTH
    return false if line_list(column).any? { |had| had.casecmp?(text) }

    update!(column => [ self[column].presence, text ].compact.join("\n"))
    @story_avoid = nil
    narrate("New for this table, #{SAID.fetch(kind.to_s)}: #{text}.")
    true
  end

  private

  # What the story matcher keeps out of every line it offers: every line
  # and veil, read once a request (Campaign#reload forgets it).
  def story_avoid
    @story_avoid ||= every_line + every_veil
  end
end
