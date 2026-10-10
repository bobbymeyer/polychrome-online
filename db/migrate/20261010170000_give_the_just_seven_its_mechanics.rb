# frozen_string_literal: true

# The engine does now what The Just Seven's guardians did only in the GM's
# hands (docs/ODA.md, The Just Seven): grabs a blow breaks, a raccoon that
# takes from the bag, answers before the blow lands, a bird that dives on
# whoever hit it last, the rising water, a telegraph that breaks, the
# Toad's free turn, the hill's waves and Her Song's rage. This brings a
# seeded database's books and campaigns up to it.
#
# A book entry moves only where it's still as first seeded: a GM who has
# changed it keeps theirs. A campaign's dungeon rooms gain their field and
# waves where the room still holds what the seed put there.
class GiveTheJustSevenItsMechanics < ActiveRecord::Migration[8.1]
  # Each changed move's effects and words as first seeded.
  MOVES = {
    "clamp" => [ [ { "primitive" => "physical", "power" => 70 }, { "primitive" => "status", "kind" => "stop", "chance" => 100, "duration" => 2 } ],
                 "Caught, and squeezed. Heat, rhythm or grease opens the claw; force only tightens it." ],
    "coil" => [ [ { "primitive" => "physical", "power" => 60 }, { "primitive" => "status", "kind" => "stop", "chance" => 100, "duration" => 2 } ],
                "Wrapped, and squeezed. Strike the snake and the coils tear free, and that hurts too." ],
    "grab" => [ [ { "primitive" => "physical", "power" => 80 }, { "primitive" => "status", "kind" => "stop", "chance" => 100, "duration" => 1 } ],
                "An arm from the dark water, and then it doesn't let go." ],
    "pilfer" => [ [ { "primitive" => "physical", "power" => 60 }, { "primitive" => "steal", "chance" => 70, "boon" => 1 } ], "Whatever's shiny, into the hoard." ],
    "circle" => [ [ { "primitive" => "away", "who" => "self", "duration" => 2 } ], "Up into the rafters, out of a blade's reach. A shot still finds it." ],
    "dive" => [ [ { "primitive" => "physical", "power" => 280, "type" => "flying" } ], "It names its mark, folds its wings, and drops." ],
    "belly_flash" => [ [ { "primitive" => "elemental", "type" => "fire", "power" => 24 } ], "It arches, shows a belly red as a forge, and then the forge opens." ],
    "tide_call" => [ [ { "primitive" => "elemental", "type" => "water", "power" => 40 } ], "It croaks, the Sword hums back, and the sea starts coming in." ],
    "her_song" => [ [ { "primitive" => "status", "kind" => "confuse", "chance" => 50, "duration" => 2 } ],
                    "Her taunt through the walls. Everyone in the room wants to hit their brother." ]
  }.freeze
  # Scripts as first seeded, by the rules that changed.
  ANSWERS = { "riposte" => "struck", "hot_skin" => "struck" }.freeze
  GRUDGES = %w[hooked_bill dive].freeze
  BIRDS = %w[cormorant cormorant_frenzied].freeze
  # A room's fight, as the seed first had it, and what it brings now.
  ROOMS = {
    "Ankle-deep" => { "moray_eel" => 3 }, "Waist-deep" => { "barnacle_swarm" => 2 }, "Chest-deep" => { "giant_octopus" => 1 },
    "The barred sanctum" => { "die_hard" => 3 }, "The hill" => { "die_hard" => 4 }
  }.freeze

  def up
    world = World.find_by(slug: "oda") or return

    require Rails.root.join("db/seeds/campaigns/just_seven").to_s
    seeded = Seeds::JustSeven::ABILITIES.transform_keys(&:to_s)
    world.abilities.where(slug: MOVES.keys).find_each do |move|
      effects, words = MOVES[move.slug]
      now = seeded.fetch(move.slug)
      changes = {}
      changes[:effects] = now[:effects].map(&:deep_stringify_keys) if move.effects == effects
      changes[:description] = now[:description] if move.description == words
      changes[:interrupt] = now[:interrupt] if now[:interrupt] && move.interrupt.zero?
      changes[:again] = true if now[:again] && !move.again?
      move.update_columns(changes) if changes.any?
    end

    world.monsters.where(slug: Seeds::JustSeven::MONSTERS.keys.map(&:to_s)).find_each do |monster|
      script = monster.ai_script.map do |rule|
        rule = rule.merge("when" => ANSWERS[rule["use"]]) if rule["when"] == "hit" && ANSWERS.key?(rule["use"])
        rule = rule.merge("target" => "last_hit") if BIRDS.include?(monster.slug) && GRUDGES.include?(rule["use"]) && !rule.key?("target")
        rule
      end
      immune = monster.status_immune.include?("confuse") && monster.slug.start_with?("amethyst_7a") ? (monster.status_immune | %w[rage]) : monster.status_immune
      monster.update_columns(ai_script: script, status_immune: immune) if script != monster.ai_script || immune != monster.status_immune
    end

    rooms!(world)
  end

  def down
    # Forward only: the seed writes the new mechanics, and the old ones were the GM's to play by hand.
  end

  private

  # The Just Seven's dungeons, in campaigns already started: each room the
  # seed pinned, if it still holds the fight it was given.
  def rooms!(world)
    places = Seeds::JustSeven::PLACES.values.flat_map { |place| Array(place[:rooms]) }.to_h { |room| [ room[:name], room[:decision].deep_stringify_keys ] }
    Location.joins(:campaign).where(campaigns: { world_id: world.id }).find_each do |location|
      pins = location.overrides.to_h.fetch("pins", {})
      changed = pins.to_h do |key, pin|
        decision = pin["decision"]
        now = places[pin["name"]]
        next [ key, pin ] unless decision && now && ROOMS[pin["name"]] == decision["monsters"] && !decision.key?("field") && !decision.key?("waves")

        [ key, pin.merge("decision" => decision.merge(now.slice("monsters", "field", "waves"))) ]
      end
      location.update_columns(overrides: location.overrides.merge("pins" => changed)) if changed != pins
    end
  end
end
