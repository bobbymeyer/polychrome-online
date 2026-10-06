# frozen_string_literal: true

# A text column written one entry a line (a world's lines and veils, a
# table's own), read as a list: stripped, blanks dropped.
module LineLists
  extend ActiveSupport::Concern

  # The entries of a column, one a line, as written: line_list(:lines).
  def line_list(attribute)
    self[attribute].to_s.lines.map(&:strip).compact_blank
  end
end
