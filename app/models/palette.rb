# frozen_string_literal: true

# The fifteen colours of the stage (docs/DESIGN.md, "Colour"): name =>
# [hex, the ink that reads on it]. Grey is the controls' colour, not a
# plate's, so it isn't offered here.
module Palette
  COLOURS = {
    "sun_yellow" => [ "#FCC010", "#111" ], "orange" => [ "#F4971B", "#111" ], "bright_red" => [ "#E9473A", "#fff" ],
    "wine_red" => [ "#CD2E55", "#fff" ], "pink" => [ "#F6BCD0", "#111" ], "greyish_green" => [ "#9DBFAE", "#111" ],
    "green" => [ "#8DC04E", "#111" ], "forest_green" => [ "#13955F", "#fff" ], "dark_green" => [ "#335F4B", "#fff" ],
    "steel_grey" => [ "#627E8B", "#fff" ], "dark_blue" => [ "#4153A1", "#fff" ], "blue" => [ "#438ECC", "#fff" ],
    "turquoise" => [ "#1EB8D1", "#111" ], "lake_green" => [ "#088EA7", "#fff" ]
  }.freeze

  module_function

  def names
    COLOURS.keys
  end

  # A chosen colour, or one picked from the key: the same key always gets
  # the same colour.
  def pick(key, chosen = nil)
    COLOURS.fetch(chosen.presence.to_s) { COLOURS.values[Zlib.crc32(key.to_s.downcase) % COLOURS.size] }
  end

  def label(name)
    name.to_s.humanize
  end
end
