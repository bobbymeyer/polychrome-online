# frozen_string_literal: true

# The Just Seven's guardians, tuned from a simulated playtest (docs/ODA.md,
# The Just Seven): more HP, so a guardian lasts six or eight rounds rather
# than four; harder blows from the physical hitters, now that the party's
# armour is counted; the Toad's burst brought down. The Soldier hits a
# little less hard, and the Bodyguard's Guard sets the shield too.
#
# Each number moves only where it's still the one first seeded: a GM who
# has tuned an entry already keeps theirs. The new numbers are the seed's.
class TuneTheJustSeven < ActiveRecord::Migration[8.1]
  # Each guardian's (and its forms') max HP as first seeded.
  HP = { "crab" => 600, "crab_frenzied" => 600, "raccoon" => 560, "raccoon_frantic" => 560,
         "orchid_bloom" => 620, "orchid_mantis" => 620, "orchid_mantis_molted" => 620, "orchid_mantis_full_bloom" => 620,
         "cormorant" => 640, "cormorant_frenzied" => 640, "fire_bellied_toad" => 760, "fire_bellied_toad_tide" => 760,
         "mechanical_bull" => 700, "mechanical_bull_overclocked" => 700, "viper" => 650,
         "amethyst_7a" => 1000, "amethyst_7a_overcharged" => 1000 }.freeze
  # A move's effect as first seeded: [effect index, field, value].
  MOVES = { "pincer" => [ 0, "power", 120 ], "twin_pincer" => [ 0, "power", 100 ], "scratch" => [ 0, "power", 110 ],
            "junk_toss" => [ 0, "power", 70 ], "junk_avalanche" => [ 0, "power", 95 ], "hooked_bill" => [ 0, "power", 120 ],
            "dive" => [ 0, "power", 240 ], "gore" => [ 0, "power", 140 ], "stampede" => [ 0, "power", 100 ],
            "fangs" => [ 0, "power", 100 ], "autocannon" => [ 0, "power", 45 ], "belly_flash" => [ 0, "power", 45 ],
            "tide_call" => [ 0, "power", 60 ], "hot_skin" => [ 0, "chance", 100 ] }.freeze

  def up
    world = World.find_by(slug: "oda") or return

    require Rails.root.join("db/seeds/campaigns/just_seven").to_s
    monsters = Seeds::JustSeven::MONSTERS.transform_keys(&:to_s)
    world.monsters.where(slug: HP.keys).find_each do |monster|
      next unless monster.stats["max_hp"] == HP[monster.slug]

      monster.update_columns(stats: monster.stats.merge("max_hp" => monsters.fetch(monster.slug)[:stats][:max_hp]))
    end

    abilities = Seeds::JustSeven::ABILITIES.merge(Seeds::Oda::ABILITIES).transform_keys(&:to_s)
    world.abilities.where(slug: MOVES.keys).find_each do |move|
      index, field, old = MOVES[move.slug]
      next unless move.effects.size == abilities.fetch(move.slug)[:effects].size && move.effects.dig(index, field) == old

      move.update_columns(effects: abilities.fetch(move.slug)[:effects].map(&:deep_stringify_keys))
    end

    guard = world.abilities.find_by(slug: "guard")
    if guard && guard.effects == [ { "primitive" => "status", "kind" => "cover", "duration" => 3 } ]
      guard.update_columns(effects: abilities.fetch("guard")[:effects].map(&:deep_stringify_keys), description: abilities.fetch("guard")[:description])
    end

    soldier = world.jobs.find_by(slug: "soldier")
    soldier.update_columns(stat_multipliers: soldier.stat_multipliers.merge("str" => 115)) if soldier&.stat_multipliers&.dig("str") == 125
  end

  def down
    # Tuning only goes forward; a GM tunes back by hand in the books.
  end
end
