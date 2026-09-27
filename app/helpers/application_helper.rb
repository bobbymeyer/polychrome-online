# frozen_string_literal: true

module ApplicationHelper
  # Each book has its own colour, used for its tabs, echoes and ground.
  BOOK_COLOURS = {
    "bestiary" => "forest_green", "compendium" => "blue", "grimoire" => "lake_green", "armory" => "orange",
    "encounters" => "dark_green", "gazetteer" => "steel_grey", "generation" => "sun_yellow"
  }.freeze

  def current_book
    BOOK_COLOURS.keys.find { |key| controller_path.start_with?("#{key}/") }
  end

  # The page's accent: its book's colour, or dark blue at the table. Pass a
  # book to colour one section as that book (the world's shelf does).
  def accent_style(book = current_book)
    hex, ink = Palette::COLOURS.fetch(BOOK_COLOURS.fetch(book.to_s, "dark_blue"))
    "--accent: #{hex}; --accent-ink: #{ink};"
  end

  # A lettered plate's colour: the one chosen for it, or one picked from its
  # name, so a Goblin is the same colour in the Bestiary, in battle and at
  # the table.
  def plate_style(key, colour = nil)
    hex, ink = Palette.pick(key, colour)
    "--plate: #{hex}; --plate-ink: #{ink};"
  end

  # For forms: "From its name" first, then the palette.
  def colour_options(selected)
    options_for_select([ [ "From its name", "" ] ] + Palette.names.map { |n| [ Palette.label(n), n ] }, selected.to_s)
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
