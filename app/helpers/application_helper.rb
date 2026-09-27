# frozen_string_literal: true

module ApplicationHelper
  # The palette (docs/DESIGN.md, "Colour"): name => [hex, the ink that reads on it].
  PALETTE = {
    "sun_yellow" => [ "#FCC010", "#111" ], "orange" => [ "#F4971B", "#111" ], "bright_red" => [ "#E9473A", "#fff" ],
    "wine_red" => [ "#CD2E55", "#fff" ], "pink" => [ "#F6BCD0", "#111" ], "greyish_green" => [ "#9DBFAE", "#111" ],
    "green" => [ "#8DC04E", "#111" ], "forest_green" => [ "#13955F", "#fff" ], "dark_green" => [ "#335F4B", "#fff" ],
    "steel_grey" => [ "#627E8B", "#fff" ], "dark_blue" => [ "#4153A1", "#fff" ], "blue" => [ "#438ECC", "#fff" ],
    "turquoise" => [ "#1EB8D1", "#111" ], "lake_green" => [ "#088EA7", "#fff" ]
  }.freeze

  # Each book has its own colour, used for its tabs, echoes and ground.
  BOOK_COLOURS = {
    "bestiary" => "forest_green", "compendium" => "blue", "grimoire" => "lake_green", "armory" => "orange",
    "encounters" => "dark_green", "gazetteer" => "steel_grey", "generation" => "sun_yellow"
  }.freeze

  def current_book
    BOOK_COLOURS.keys.find { |key| controller_path.start_with?("#{key}/") }
  end

  # The page's accent: its book's colour, or dark blue at the table.
  def accent_style
    hex, ink = PALETTE.fetch(BOOK_COLOURS.fetch(current_book.to_s, "dark_blue"))
    "--accent: #{hex}; --accent-ink: #{ink};"
  end

  # A lettered plate's colour: the same name always gets the same one, so a
  # Goblin is the same colour in the Bestiary, in battle and at the table.
  def plate_style(key)
    hex, ink = PALETTE.values[Zlib.crc32(key.to_s.downcase) % PALETTE.size]
    "--plate: #{hex}; --plate-ink: #{ink};"
  end

  def book_nav_link(label, path, key)
    current = controller_path.start_with?("#{key}/")
    link_to label, path, class: [ "topbar__book", ("is-current" if current) ], aria: { current: (current ? "page" : nil) }
  end

  # Human label for a closed-vocabulary token: "single_enemy" -> "Single enemy".
  def term(token)
    token.to_s.humanize
  end

  def signed(number)
    number.to_i.positive? ? "+#{number}" : number.to_s
  end
end
