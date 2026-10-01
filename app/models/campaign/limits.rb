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
  def every_line = limits(world.lines, lines)
  def every_veil = limits(world.veils, veils)

  # Only the table's own.
  def table_lines = limits(lines)
  def table_veils = limits(veils)

  # Adds a line ("line") or a veil ("veil") to this table's and tells the
  # table, with no name on it. Adding one already there changes nothing.
  def draw_limit!(kind, text)
    column = KINDS.fetch(kind.to_s) { raise Refusal, "A line or a veil, nothing else." }
    text = text.to_s.squish
    raise Refusal, "Say what it is." if text.empty?
    raise Refusal, "Keep it short: #{MAX_LENGTH} characters at most." if text.length > MAX_LENGTH
    return false if limits(self[column]).any? { |had| had.casecmp?(text) }

    update!(column => [ self[column].presence, text ].compact.join("\n"))
    narrate("New for this table, #{SAID.fetch(kind.to_s)}: #{text}.")
    true
  end

  private

  def limits(*texts)
    texts.flat_map { |text| text.to_s.lines.map(&:strip) }.compact_blank.uniq
  end
end
