# frozen_string_literal: true

# Dead Calm: a campaign in Oda, from Bobby's design document ("Kaiju Mecha
# Campaign"). A wind-stranded island city sits on the body of a buried
# kaiju-mecha; the party finds seven masks, routes light through two prisms
# and wakes her, just as her ancient brother and rival arrives to finish an
# old fight. About eight sessions: the smoke lounge, seven five-room
# dungeons (Legs, Arms, Sword, Torso, Head), then the Giant Battle, which
# isn't built yet.
#
# Started for a GM with bin/rails "campaigns:seed[dead_calm,gm@example.com]".
# It adds what it needs to Oda's books (only what's missing), then makes
# the campaign: the island's map and dungeons, the cast, the Seven Signs,
# the secrets, the scenes and the GM's checklist. The campaign starts from
# a blank map, not Oda's atlas: the island is cut off from the mainland.
require_relative "../setting"
require_relative "../oda"

module Seeds
  module DeadCalm
    NAME = "Dead Calm"

    module_function

    # The campaign, made for the GM (or found, if they already have it).
    def run(gm: nil)
      world = Oda.run
      add_books(world)
      world.campaigns.find_by(name: NAME, gm: gm) || Campaign.transaction { start(world, gm) }
    end

    # Forms first: a phase can only become an entry that's in the Bestiary.
    def add_books(world)
      forms = MONSTERS.values.flat_map { |attrs| Array(attrs[:phases]).map { |phase| phase[:becomes].to_sym } }
      Setting.new(slug: "oda", world: Oda::WORLD, abilities: ABILITIES, items: ITEMS,
                  monsters: MONSTERS.sort_by { |slug, _| forms.include?(slug) ? 0 : 1 }.to_h,
                  generator_tables: GENERATOR_TABLES, location_templates: LOCATION_TEMPLATES).run
    end

    def start(world, gm)
      campaign = world.campaigns.create!(name: NAME, gm: gm)
      map = campaign.maps.create!(name: "The Island", description: "A city climbing an island's slope from the quays to the dome, in a sea with no wind.")
      nodes = PLACES.to_h { |name, attrs| [ name, place!(campaign, map, name, attrs) ] }
      ROADS.each { |from, to, attrs| campaign.map_edges.create!(from_node: nodes.fetch(from), to_node: nodes.fetch(to), **attrs) }
      cast = CAST.to_h { |name, attrs| [ name, cast!(campaign, nodes, name, attrs) ] }
      story!(campaign, nodes, cast)
      campaign.set_out!(from_the_setting: false)
      RUMOURS.each { |rumour| campaign.start_rumour!(rumour, at: nodes.fetch("The Steps")) }
      campaign
    end

    def place!(campaign, map, name, attrs)
      node = campaign.map_nodes.create!(map: map, name: name, kind: attrs[:kind], x: attrs[:x], y: attrs[:y], visible: attrs[:visible],
                                        description: attrs[:description], notes: attrs[:notes])
      Array(attrs[:modes]).each { |mode| node.add_mode!(mode) }
      if attrs[:template]
        template = campaign.world.location_templates.find_by!(slug: attrs[:template])
        node.update!(location: campaign.locations.create!(location_template: template, overrides: { "name" => name }))
      elsif attrs[:rooms]
        node.update!(location: dungeon!(campaign, name, attrs))
      end
      node
    end

    # A five-room dungeon: a chain rolled from the template, its rooms pinned
    # to the story's in order, entrance to guardian, and the twist added
    # past the guardian's room.
    def dungeon!(campaign, name, attrs)
      template = campaign.world.location_templates.find_by!(slug: "five_rooms")
      rooms = attrs[:rooms].map(&:deep_stringify_keys)
      seed = chain_seed(template, rooms.size)
      chain = Generators::Dungeon.generate(seed: seed, template: template.settings, encounters: [], tables: template.table_entries)["rooms"]
                                 .sort_by { |room| room["depth"] }
      pins = chain.zip(rooms).to_h { |room, story| [ room["key"], story ] }
      added = attrs.fetch(:twist, []).each_with_index.map do |twist, i|
        decision = twist[:decision] || { kind: "event", text: twist[:text] }
        { "key" => "added-#{i + 1}", "name" => twist[:name], "decision" => decision.deep_stringify_keys,
          "connect" => i.zero? ? chain.last["key"] : "added-#{i}" }
      end
      campaign.locations.create!(location_template: template, seed: seed,
                                 overrides: { "name" => name, "pins" => pins, "added_rooms" => added })
    end

    # The first seed that rolls the rooms as one corridor, each a step
    # deeper than the last: the five-room shape, never a branch.
    def chain_seed(template, count)
      (1..).find do |seed|
        rooms = Generators::Dungeon.generate(seed: seed, template: template.settings, encounters: [], tables: template.table_entries)["rooms"]
        rooms.size == count && rooms.map { |room| room["depth"] }.sort == (0...count).to_a
      end
    end

    def cast!(campaign, nodes, name, attrs)
      monster = attrs[:monster] && campaign.world.monsters.find_by!(slug: attrs[:monster])
      campaign.npcs.create!(name: name, title: attrs[:title], description: attrs[:description], monster: monster,
                            location: attrs[:place] && nodes.fetch(attrs[:place]).location)
    end

    def story!(campaign, nodes, cast)
      CLOCKS.each do |clock|
        mode = clock[:mode] && nodes.fetch(clock[:place]).modes.find_by!(name: clock[:mode])
        campaign.clocks.create!(name: clock[:name], segments: clock[:segments], impulse: clock[:impulse], portents: clock[:portents],
                                full_line: clock[:full_line], mode: mode, map_node: clock[:source] && nodes.fetch(clock[:source]))
      end
      SECRETS.each do |secret|
        campaign.secrets.create!(key: secret[:key], body: secret[:body], steps: secret[:steps],
                                 npc: secret[:npc] && cast.fetch(secret[:npc]), location: secret[:place] && nodes.fetch(secret[:place]).location)
      end
      SCENES.each do |scene|
        campaign.scenes.create!(name: scene[:name], script: scene[:script], ending: scene.fetch(:ending, "none"),
                                encounter: scene.fetch(:encounter, {}).transform_keys(&:to_s), map_node: scene[:reveal] && nodes.fetch(scene[:reveal]))
      end
      FLAGS.each { |key, (value, note)| campaign.flags.create!(key: key, value: value, note: note) }
    end
  end
end

require_relative "dead_calm/books"
require_relative "dead_calm/places"
require_relative "dead_calm/cast"
require_relative "dead_calm/story"
