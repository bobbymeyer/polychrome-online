# frozen_string_literal: true

# Form values arrive as strings; JSON columns hold the engine's types.
# Blank means "not set". A value that isn't a whole number is kept as-is so
# validation can report it instead of silently becoming 0.
module JsonCasting
  module_function

  def integer(value)
    return value if value.is_a?(Integer)
    return nil if value.blank?

    Integer(value.to_s.strip, 10)
  rescue ArgumentError
    value
  end

  # Form rows arrive as { "0" => {...}, "1" => {...} }; seeds pass arrays.
  def rows(value)
    rows = value.is_a?(Hash) || value.is_a?(ActionController::Parameters) ? value.to_h.sort_by { |k, _| k.to_i }.map(&:last) : Array(value)
    rows.map { |row| row.to_h.stringify_keys }
  end

  def integer?(value)
    value.is_a?(Integer)
  end
end
