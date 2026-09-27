# frozen_string_literal: true

# Plain generator inputs for the pure generator specs.
module GeneratorFixtures
  module_function

  def texts(*strings)
    strings.map { |text| { "text" => text } }
  end

  def town_tables
    {
      "town_names" => texts("Tule", "Carwen", "Walse"),
      "names" => texts("Mira", "Oskar", "Lenne", "Dorn", "Pell", "Hask", "Ivy", "Brand"),
      "hooks" => texts("Owes the guild money.", "Saw lights on the hill.", "Lost a brother to the pass.",
                       "Sells maps that are mostly right.", "Wants an escort north.", "Hides a runaway."),
      "service_names" => [ { "text" => "The Sleepy Chocobo", "service" => "inn" }, { "text" => "Odds & Ends", "service" => "shop" },
                           { "text" => "Adventurers' Hall", "service" => "guild" }, { "text" => "Chapel of Light", "service" => "temple" } ],
      "buildings" => [ { "text" => "Inn", "service" => "inn", "width" => 90, "height" => 90, "roof" => "peak" },
                       { "text" => "Shop", "service" => "shop", "width" => 70, "height" => 70 },
                       { "text" => "Guild", "service" => "guild", "width" => 80, "height" => 100, "roof" => "flat" },
                       { "text" => "Temple", "service" => "temple", "width" => 70, "height" => 130, "roof" => "dome" },
                       { "text" => "House", "width" => 50, "height" => 60, "weight" => 3 },
                       { "text" => "Tower", "width" => 40, "height" => 120 } ],
      "stock" => %w[potion hi_potion phoenix_down broadsword dagger rod leather_cap].map { |item| { "item" => item } }
    }
  end

  def town_template
    { "services" => { "inn" => 100, "shop" => 100, "guild" => 50, "temple" => 50 }, "npcs" => [ 3, 6 ], "stock" => [ 3, 5 ], "buildings" => [ 7, 11 ] }
  end

  def dungeon_tables
    {
      "dungeon_names" => texts("Wind Shrine", "Pirate Cave"),
      "rooms" => texts("Flooded Hall", "Ossuary", "Collapsed Stair", "Shrine", "Guardroom", "Cistern", "Vault", "Crossing"),
      "room_events" => texts("A voice asks for a name.", "The floor tilts.", "Old bones, arranged in a circle."),
      "forks" => texts("A rope bridge: someone must stay behind to hold it.", "Poison gas: everyone loses 10% HP."),
      "treasure" => [ { "item" => "potion", "weight" => 3 }, { "item" => "phoenix_down" } ]
    }
  end

  def dungeon_template
    { "rooms" => [ 6, 10 ], "loops" => 2, "decisions" => { "encounter" => 4, "event" => 2, "treasure" => 2, "fork" => 2 } }
  end

  def encounters
    [ { "weight" => 3, "monsters" => { "goblin" => 3 } }, { "weight" => 1, "monsters" => { "goblin_chief" => 1, "goblin" => 2 } } ]
  end
end
