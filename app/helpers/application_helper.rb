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
  # The music a page asks for (sound.js): its own scene's track, unless the
  # GM has chosen one for the table. A battle is fixed: it keeps its music
  # whatever the GM picks. An empty track is silence.
  def music_meta(campaign, scene, fixed: false)
    return unless campaign

    world = campaign.world
    chosen = fixed ? scene : (campaign.music || scene)
    tag.meta(name: "polychrome-music", content: world.music_path(chosen).to_s,
             data: { default: world.music_path(scene).to_s, fixed: fixed })
  end

  # A QR code as inline SVG (local co-op: scan the shared screen to join).
  def qr_svg(url)
    RQRCode::QRCode.new(url).as_svg(module_size: 6, standalone: true, use_path: true, viewbox: true,
                                    color: "000", shape_rendering: "crispEdges").sub(/\A<\?xml[^>]*\?>/, "").html_safe # rubocop:disable Rails/OutputSafety -- generated SVG, no user markup
  end

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
  # A status and a service go by the world's word for it (Vocabulary).
  def term(token, world = vocabulary_world)
    token = token.to_s
    return word("status.#{token}", world) if Battle::STATUSES.include?(token)
    return word("service.#{token}", world) if World::Vocabulary::SERVICES.include?(token)

    token.humanize
  end

  # What a check can be made with: the world's skills first, then the bare
  # stats. A skill is posted as "skill:<slug>" (Campaign#check!).
  def check_options(world, selected = nil)
    skills = Array(world.skills).map { |s| [ "#{s['name']} (#{stat_label(s['stat'])})", "skill:#{s['slug']}" ] }
    stats = Stats::Check::STATS.map { |s| [ stat_label(s), s ] }
    grouped_options_for_select({ "Skills" => skills, "Stats" => stats }, selected)
  end

  def signed(number)
    number.to_i.positive? ? "+#{number}" : number.to_s
  end
end
