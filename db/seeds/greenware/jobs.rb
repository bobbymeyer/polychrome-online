# frozen_string_literal: true

# The Compendium: nine archetypes, each a trade of the valley. Only the
# unfired have one; the fired are what they are. (Seeds::Greenware)
module Seeds
  module Greenware
    # What time spent on things to do pays someone in the trade, at the next rest (Job#payoff).
    PAYOFFS = {
      "greenhand" => { "kind" => "money", "amount" => 20, "line" => "{who} picks up odd work in the yards: {amount}." },
      "thrower" => { "kind" => "exp", "amount" => 20, "line" => "{who} throws until the wheel stops: {amount}." },
      "firekeeper" => { "kind" => "abp", "amount" => 2, "line" => "{who} keeps a small fire going all night, and learns from it: {amount}." },
      "mender" => { "kind" => "rumour", "amount" => 1, "line" => "{who} sits with the cracked, and hears something: {rumour}" },
      "shardwalker" => { "kind" => "money", "amount" => 40, "line" => "{who} comes back from the Flats with {amount} and no cuts to show for it." },
      "slipcaster" => { "kind" => "abp", "amount" => 2, "line" => "{who} talks with the small slip things: {amount}." },
      "wedger" => { "kind" => "exp", "amount" => 25, "line" => "{who} wedges clay until their arms shake: {amount}." },
      "collier" => { "kind" => "rumour", "amount" => 1, "line" => "{who} burns a stack in the woods, and the woods talk: {rumour}" },
      "salter" => { "kind" => "money", "amount" => 30, "line" => "{who} sells salt on the quay: {amount}." }
    }.freeze

    JOBS = {
      greenhand: { name: "Greenhand", base_type: "clay", skills: %w[hands haggling], field_ability: "odd_jobs", signature: "muck_in", desperation: "last_push",
                   description: "Unfired and unfinished: anyone, for now. Every hero in the valley starts here, and some never leave.",
                   stat_multipliers: {}, ability_slots: 2, equip_categories: Item::EQUIPMENT_CATEGORIES, innates: [],
                   levels: [ [ "read_the_cone", 1 ], [ "slake", 12 ], [ "twice_round", 20 ], [ "stoke_up", 28 ], [ "glaze_coat", 36 ], [ "spin_up", 50 ] ] },
      thrower: { name: "Thrower", base_type: "clay", skills: %w[heft standing], field_ability: "shoulder_the_door", signature: "centre", passive: "second_wind", desperation: "collapse_the_wall",
                 description: "Thrown thick on the wheel and proud of it. A wheel bat in one hand, a paddle in the other, and the resolve to stand in front.",
                 stat_multipliers: { max_hp: 130, str: 120, vit: 120, agi: 90, mag: 60 },
                 equip_categories: %w[sword axe spear shield helmet heavy_armor accessory], innates: [ { stat: "def", percent: 10 } ],
                 levels: [ [ "stoke_up", 1 ], [ "chip", 6 ], [ "twice_round", 14 ], [ "bat_shove", 22 ], [ "stand_firm", 34 ], [ "wheel_oath", 50 ] ] },
      firekeeper: { name: "Firekeeper", base_type: "fire", skills: %w[firing reading], field_ability: "read_the_draft", signature: "stoke", passive: "mp_regen", desperation: "blowout",
                    description: "Keeps the small fires, and knows the big one by heart. Destruction, studied carefully, by someone the Guild won't let near a kiln.",
                    stat_multipliers: { max_hp: 70, max_mp: 150, mag: 140, str: 60 },
                    equip_categories: %w[knife rod robe hat accessory], innates: [],
                    levels: [ [ "ember", 1 ], [ "ashfall", 4 ], [ "choke", 7 ], [ "wick", 12 ], [ "blaze", 18 ], [ "craze", 23 ], [ "settle", 28 ],
                              [ "draw_off", 33 ], [ "ash_storm", 40 ], [ "white_heat", 50 ] ] },
      mender: { name: "Mender", base_type: "water", skills: %w[reading haggling], field_ability: "field_mend", signature: "patch", passive: "regen", desperation: "shatter",
                description: "Mends the cracked with gold along the break, the old way. Keeps everyone else whole, and asks what they did to get like that.",
                stat_multipliers: { max_hp: 80, max_mp: 140, mag: 120, spr: 130, str: 60 },
                equip_categories: %w[staff robe hat accessory], innates: [ { stat: "mdef", percent: 20 } ],
                levels: [ [ "slake", 1 ], [ "glaze_coat", 7 ], [ "mend", 12 ], [ "slurry", 16 ], [ "gold_seam", 22 ], [ "spin_up", 28 ], [ "gold_flood", 38 ], [ "gold_line", 50 ] ] },
      shardwalker: { name: "Shardwalker", base_type: "glass", skills: %w[softfoot hands], field_ability: "slip_the_latch", signature: "lift", passive: "first_strike", desperation: "thousand_shards",
                     description: "Salvages the Glass Flats barefoot and comes back with other people's things. Fast hands, faster feet, no cuts.",
                     stat_multipliers: { agi: 140, str: 90, mag: 80, max_hp: 90 },
                     equip_categories: %w[knife hat light_armor accessory], innates: [ { stat: "agi", add: 5 } ],
                     levels: [ [ "palm", 1 ], [ "kiln_smoke", 6 ], [ "into_the_racks", 12 ], [ "twice_round", 18 ], [ "pocket", 34 ], [ "shard_dance", 50 ] ] },
      slipcaster: { name: "Slipcaster", base_type: "water", skills: %w[firing roadcraft], field_ability: "send_the_cat", signature: "cast_slip_cat", passive: "mp_regen", desperation: "flood",
                    description: "Pours creatures out of a bucket of slip. They come, do one thing, and run back in. The Guild calls it a child's trick; the children know better.",
                    stat_multipliers: { max_hp: 75, max_mp: 160, mag: 135, str: 55 },
                    equip_categories: %w[staff rod robe hat accessory], innates: [],
                    levels: [ [ "call_ash_moth", 1 ], [ "call_glass_finch", 4 ], [ "call_kiln_hound", 8 ], [ "call_clay_tortoise", 20 ], [ "call_slip_eel", 34 ], [ "call_bottle_wyrm", 50 ] ] },
      wedger: { name: "Wedger", base_type: "clay", skills: %w[heft reading], field_ability: "sit_still", signature: "knead", passive: "counter", desperation: "hundred_slaps",
                description: "Wedges clay all day: slam, fold, slam. Fists instead of tools, and arms that don't know when to stop.",
                stat_multipliers: { max_hp: 140, str: 130, vit: 110, mag: 50 },
                equip_categories: %w[light_armor accessory], innates: [ { stat: "atk", add: 12 } ],
                levels: [ [ "sweep", 1 ], [ "stoke_up", 8 ], [ "overfire", 16 ], [ "grudge", 24 ], [ "breathe", 34 ], [ "final_press", 50 ] ] },
      collier: { name: "Collier", base_type: "ash", skills: %w[roadcraft standing], field_ability: "read_the_land", signature: "rake_the_ash", passive: "regen", desperation: "kiln_collapse",
                 description: "Burns the woods for the kilns, in rotation, and reads the land by what it will burn. Borrows its temper.",
                 stat_multipliers: { max_hp: 100, mag: 115, spr: 115, str: 90 },
                 equip_categories: %w[staff axe light_armor hat accessory], innates: [ { stat: "mdef", percent: 10 } ],
                 levels: [ [ "cinder_pit", 1 ], [ "ash_cloud", 8 ], [ "lye", 16 ], [ "kiln_quake", 26 ], [ "mulch", 36 ], [ "ash_wrath", 50 ] ] },
      salter: { name: "Salter", base_type: "glass", skills: %w[haggling hands], field_ability: "talk_the_price", signature: "salt_glaze", passive: "regen", desperation: "brine_storm",
                description: "Works the estuary pans and knows a little of everything: fire, water, glass, and the price of each. A paddle to put it through.",
                stat_multipliers: { max_hp: 95, max_mp: 115, str: 105, mag: 110 },
                equip_categories: %w[sword knife rod light_armor robe hat accessory], innates: [],
                levels: [ [ "douse", 1 ], [ "slake", 1 ], [ "ember", 5 ], [ "shard", 8 ], [ "wet_hands", 12 ], [ "leather_hard", 16 ], [ "cool", 22 ],
                          [ "spin_up", 28 ], [ "hot_hands", 36 ], [ "brine_rain", 50 ] ] }
    }.freeze
  end
end
