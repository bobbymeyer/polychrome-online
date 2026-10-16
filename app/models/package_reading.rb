# frozen_string_literal: true

# Reading a package's JSON (PackageArchive), which is someone else's file:
# each value is taken only in the shape its field holds, and anything else
# is as good as absent, so a wrong type is never a crash. A list of records
# keeps only its records, and one far longer than any real prep is refused
# rather than written row by row.
module PackageReading
  # More rows of one kind than any campaign or world has.
  MAX_ROWS = 5_000

  private

  def text(value) = value.is_a?(String) ? value : nil
  def int(value) = JsonCasting.integer(value)
  def list(value) = value.is_a?(Array) ? value : []
  def hash(value) = value.is_a?(Hash) ? value : {}

  # A list of records (maps, places, flags…): only its hashes.
  def records(value)
    rows = list(value)
    raise Refusal, "That file has #{rows.size} of something, more than any real one has (#{MAX_ROWS} at most)." if rows.size > MAX_ROWS

    rows.select { |row| row.is_a?(Hash) }
  end
end
