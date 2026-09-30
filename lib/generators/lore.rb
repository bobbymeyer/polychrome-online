# frozen_string_literal: true

module Generators
  # A world's lore: the words its histories and provenance are made from.
  # What trades its families follow and what they make, what a dungeon was
  # before it was a dungeon, how places fall, what people quarrel over,
  # how they betray each other, what goes well for them, where they drown,
  # how a thing changes hands, and what people say overnight when someone
  # is seen somewhere or a road is raided. Each is one of the world's generator
  # tables (GeneratorTable::LORE_KINDS), so every setting has its own and
  # edits them; a world without one simply has none of that happen.
  #
  #   { "trades" => { "smith" => ["blade", "helm"], "brewer" => [] },
  #     "pasts" => { "manor" => { "rooms" => [...], "heart" => "Master Bedchamber", "keeps" => [...], "named" => ["manor", "hall"] } },
  #     "falls" => { "fire" => { "did", "sealed", "trace", "dead", "town" => "A fire took half of %s" } },
  #     "quarrels" => [...], "betrayals" => [...], "fortunes" => [...], "waters" => [...], "owners" => ["Pawned by a %s", ...],
  #     "sightings" => ["{who} was seen in {where}."], "raids" => ["A caravan on the road between {from} and {to} was attacked."] }
  #
  # Pure.
  module Lore
    LISTS = %w[quarrels betrayals fortunes waters owners sightings raids].freeze
    KINDS = (%w[trades pasts falls] + LISTS).freeze

    # What the Base World starts with (db/seeds), and what worlds made
    # before lore was theirs were given. Never read while playing.
    STARTER = {
      "trades" => { "smith" => %w[blade helm spear axe], "brewer" => [], "miller" => [], "ferryman" => [], "weaver" => %w[cloak banner],
                    "merchant" => [], "fisher" => [], "chandler" => [], "jeweller" => %w[ring locket circlet], "mason" => %w[seal effigy] },
      "pasts" => {
        "manor" => { "rooms" => [ "Great Hall", "Kitchens", "Nursery", "Wine Cellar", "Portrait Gallery", "Servants' Stair", "Library", "Family Chapel" ],
                     "heart" => "Master Bedchamber", "keeps" => %w[signet portrait ewer], "named" => %w[manor hall house estate lodge] },
        "mine" => { "rooms" => [ "Pithead", "Cart Run", "Shored Gallery", "Flooded Drift", "Powder Store", "Winding House", "Tally Office" ],
                    "heart" => "The Deep Seam", "keeps" => %w[lamp pick nugget], "named" => %w[mine quarry pit seam delve dig] },
        "abbey" => { "rooms" => [ "Cloister", "Scriptorium", "Refectory", "Dormitory", "Infirmary", "Undercroft", "Chapter House", "Bell Tower" ],
                     "heart" => "The Reliquary", "keeps" => %w[reliquary psalter censer], "named" => %w[abbey priory chapel temple shrine monastery cloister] },
        "fort" => { "rooms" => [ "Gatehouse", "Armoury", "Barracks", "Stores", "Cells", "Stables", "Well Court", "Signal Tower" ],
                    "heart" => "The Keep", "keeps" => %w[banner horn warrant], "named" => %w[fort keep castle citadel garrison bastion watch] },
        "tower" => { "rooms" => [ "Long Stair", "Study", "Observatory", "Laboratory", "Map Room", "Stores" ],
                     "heart" => "The Top Room", "keeps" => %w[astrolabe journal staff], "named" => %w[tower spire observatory lighthouse] },
        "tomb" => { "rooms" => [ "Mourners' Walk", "Ossuary", "Chapel of Rest", "Sealed Niches", "Embalming Room", "Offering Hall" ],
                    "heart" => "The First Tomb", "keeps" => %w[crown ring urn], "named" => %w[crypt tomb barrow grave catacomb ossuary mound vault] }
      },
      "falls" => {
        "fire" => { "did" => "burned", "sealed" => "sealed after the fire", "trace" => "Scorched beams, and a smell of smoke that never left.",
                    "dead" => "who burned with it", "town" => "A fire took half of %s" },
        "flood" => { "did" => "flooded", "sealed" => "left to the water", "trace" => "A tide line on the walls, higher than your head.",
                     "dead" => "who drowned in it", "town" => "The river rose through %s" },
        "plague" => { "did" => "took the sickness", "sealed" => "sealed with the sick inside", "trace" => "Doors chalked with a cross, from the outside.",
                      "dead" => "who died of the sickness there", "town" => "Sickness came to %s" },
        "collapse" => { "did" => "fell in", "sealed" => "never dug out", "trace" => "Rubble, and a hand-cart still half full.",
                        "dead" => "who was under it when it fell" },
        "curse" => { "did" => "went wrong", "sealed" => "bricked up and blessed", "trace" => "Every mirror turned to face the wall.",
                     "dead" => "who never came out" }
      },
      "quarrels" => [ "a boundary stone moved in the night", "a horse sold lame", "a debt never paid", "a broken betrothal",
                      "water rights on the mill race", "a pew in the temple", "a song about them sung at a wedding", "a dog that killed sheep",
                      "the price of a bridge toll", "who found the spring first" ],
      "betrayals" => [ "informed on them to the tax-men", "bought their debts and called them in", "burned their stores and blamed the weather",
                       "married into them for the land and left", "sold their secret to a rival house" ],
      "fortunes" => [ "a good harvest", "a lucky ship", "a rich marriage", "a new mill" ],
      "waters" => [ "the river", "the millpond", "the lake", "the sea" ],
      "owners" => [ "Pawned by a %s, who never came back for it", "Sold off by the %s family in a lean year", "Taken from a %s in a card game",
                    "Made for a %s wedding that never happened", "A %s's, until the feud" ],
      "sightings" => [ "{who} was seen in {where}." ],
      "raids" => [ "A caravan on the road between {from} and {to} was attacked." ]
    }.freeze

    module_function

    def empty = KINDS.to_h { |kind| [ kind, LISTS.include?(kind) ? [] : {} ] }

    # From a world's lore tables: { kind => [entry, ...] }, entries as the
    # tables keep them (lists as text with commas).
    def from_tables(tables)
      lore = empty
      tables.each do |kind, entries|
        Array(entries).each do |entry|
          name = entry["text"].to_s.strip
          next if name.empty?

          case kind.to_s
          when "trades" then lore["trades"][name.downcase] = list(entry["makes"])
          when "pasts"
            lore["pasts"][name.downcase] = { "rooms" => list(entry["rooms"]), "heart" => text(entry["heart"]),
                                             "keeps" => list(entry["keeps"]), "named" => list(entry["named"]).map(&:downcase) }
          when "falls"
            lore["falls"][name.downcase] = entry.slice("did", "sealed", "trace", "dead", "town").transform_values { |v| v.to_s.strip }.reject { |_, v| v.empty? }
          when *LISTS then lore[kind.to_s] << name
          end
        end
      end
      lore
    end

    # As tables: [kind, entries] pairs, for seeding a world.
    def to_tables(lore = STARTER)
      [
        [ "trades", lore["trades"].map { |name, makes| { "text" => name, "makes" => text(makes.join(", ")) }.compact } ],
        [ "pasts", lore["pasts"].map do |name, was|
          { "text" => name, "rooms" => was["rooms"].join(", "), "heart" => was["heart"], "keeps" => was["keeps"].join(", "),
            "named" => was["named"].join(", ") }.compact
        end ],
        [ "falls", lore["falls"].map { |name, fall| { "text" => name }.merge(fall) } ]
      ] + LISTS.map { |kind| [ kind, lore[kind].map { |text| { "text" => text } } ] }
    end

    def list(text) = text.to_s.split(",").map(&:strip).reject(&:empty?)

    # A line with its {placeholders} filled in: fill("{who} was seen in {where}.", who: "Mara", where: "Tule").
    def fill(line, **values)
      values.reduce(line.to_s) { |text, (key, value)| text.gsub("{#{key}}", value.to_s) }
    end

    # Trimmed, or nil when there's nothing there.
    def text(value)
      trimmed = value.to_s.strip
      trimmed.empty? ? nil : trimmed
    end

    # What a place was, going by its name: the Drowned Abbey was an abbey,
    # Tsukiura Station a station (a word of its name, or that word plural).
    def was_for(name, lore)
      words = name.to_s.downcase.scan(/[[:alnum:]']+/)
      words += words.map { |word| word.delete_suffix("s") }
      lore["pasts"].find { |_, was| (was["named"] & words).any? }&.first
    end
  end
end
