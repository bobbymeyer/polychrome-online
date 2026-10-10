# frozen_string_literal: true

# The Compendium: Oda's archetypes (docs/ODA.md). Each has its type, its
# skills, its move outside battle, its signature, its passive, its last
# move and its learn table. (Seeds::Oda)
module Seeds
  module Oda
    MANCER_NAMES = { "fire" => "Firemancer", "water" => "Watermancer", "thunder" => "Thundermancer", "earth" => "Earthmancer", "wind" => "Windmancer" }.freeze
    MANCER_WORDS = {
      "fire" => "Red salt and a short temper. Burns what the others only singe.",
      "water" => "Blue salt, patient as a river. Slows what it can't drown.",
      "thunder" => "Yellow salt and a spark. Fast, loud, and sometimes nobody moves afterwards.",
      "earth" => "Grey salt, heavy as a hill. Stands between the party and the worst of it.",
      "wind" => "Green salt and a light step. Puts people where they ought to be, which is elsewhere."
    }.freeze

    # What time spent on things to do pays someone in the archetype, at the
    # next rest (Job#payoff). A coward is paid nothing (Character::Courage).
    PAYOFFS = {
      "courtsword" => { "kind" => "money", "amount" => 30, "line" => "{who} stands guard for a merchant through the noon heat: {amount}." },
      "thief" => { "kind" => "money", "amount" => 40, "line" => "{who} comes back with {amount} and no explanation." },
      "monk" => { "kind" => "exp", "amount" => 25, "line" => "{who} runs the forms until the sun goes down: {amount}." },
      "magician" => { "kind" => "money", "amount" => 30, "line" => "{who} mends a clock or three in the market: {amount}." },
      "healer" => { "kind" => "rumour", "amount" => 1, "line" => "{who} sits with the powder-sick, and hears something: {rumour}" },
      "ranger" => { "kind" => "money", "amount" => 30, "line" => "{who} brings in pelts from the mesas: {amount}." },
      "soldier" => { "kind" => "money", "amount" => 35, "line" => "{who} drills the town watch until they can tell a pike from a broom: {amount}." },
      "bodyguard" => { "kind" => "money", "amount" => 40, "line" => "{who} walks a merchant and his strongbox home through the dusk: {amount}." }
    }.merge(MANCER_NAMES.keys.to_h { |type| [ "#{type}mancer", { "kind" => "abp", "amount" => 2, "line" => "{who} grinds and measures #{type} salt: {amount}." } ] }).freeze

    def self.mancer_jobs
      MANCER_POWDERS.to_h do |name, powder|
        single, spread, double, top = powder[:tiers].map(&:downcase)
        [ :"#{name}mancer", { typed_attack: false, name: MANCER_NAMES.fetch(name), base_type: powder.fetch(:type), skills: [ MANCER_SKILLS.fetch(name), "powdercraft" ].uniq,
                              field_ability: powder[:field].first, signature: powder[:load].first, passive: "mp_regen", desperation: powder[:last].first, description: "A specialist in one powder. #{MANCER_WORDS.fetch(name)}",
                              stat_multipliers: { max_hp: 70, max_mp: 150, mag: 140, str: 60 },
                              equip_categories: %w[rod staff robe hat accessory], innates: [],
                              levels: [ [ single, 1 ], [ powder[:trick].first, 6 ], [ spread, 10 ], [ double, 20 ], [ top, 40 ] ] } ]
      end
    end

    JOBS = {
      courtsword: { name: "Courtsword", base_type: "steel", skills: %w[draw nerve], field_ability: "stare_down", signature: "sheathe", passive: "second_wind",
                    desperation: "thousand_cuts",
                    description: "A calm figure who waits, and waits, and draws last. Then everyone else falls.",
                    stat_multipliers: { max_hp: 115, str: 130, agi: 80, vit: 105, mag: 50 },
                    equip_categories: %w[sword light_armor heavy_armor hat accessory], innates: [ { stat: "atk", add: 4 } ],
                    levels: [ [ "draw", 1 ], [ "iai_stance", 4 ], [ "zantetsuken", 10 ], [ "stillwater", 16 ], [ "moon_cut", 24 ], [ "last_light", 34 ], [ "final_draw", 50 ] ] },
      thief: { name: "Thief", base_type: "dark", skills: %w[hands draw], field_ability: "pick_lock", signature: "mug", passive: "first_strike",
               desperation: "vanishing_point",
               description: "Steals, opens locks, and reads people the way other people read signs.",
               stat_multipliers: { agi: 140, str: 90, max_hp: 90 },
               equip_categories: %w[knife hat light_armor accessory], innates: [ { stat: "agi", add: 5 } ],
               levels: [ [ "steal", 1 ], [ "smoke_bomb", 4 ], [ "blinding_dust", 8 ], [ "lift", 12 ], [ "twin_knives", 18 ], [ "hide", 22 ],
                         [ "backstab", 28 ], [ "shadowstep", 36 ], [ "grand_larceny", 50 ] ] },
      monk: { name: "Monk", base_type: "fighting", skills: %w[brawn nerve], field_ability: "meditate", signature: "palm_strike", passive: "counter",
              desperation: "hundred_fists",
              description: "Gave up powder for breath and fists. Nothing a Monk does costs a measure of anything.",
              stat_multipliers: { max_hp: 140, str: 130, vit: 110, mag: 50 },
              equip_categories: %w[light_armor accessory], innates: [ { stat: "atk", add: 12 } ],
              levels: [ [ "sweep_kick", 1 ], [ "gather_breath", 6 ], [ "dragon_fist", 12 ], [ "chakra", 18 ], [ "iron_body", 24 ], [ "revenge", 30 ], [ "seven_forms", 50 ] ] },
      magician: { typed_attack: false, name: "Magician", base_type: "psychic", skills: %w[clockwork parley], field_ability: "smoke_and_mirrors", signature: "quick",
                  passive: "mp_regen", desperation: "clockstop",
                  description: "Time, mirrors, smoke and small machines. Less damage than a Mancer; far more say in how the fight goes.",
                  stat_multipliers: { max_hp: 85, max_mp: 130, mag: 120, agi: 110, str: 70 },
                  equip_categories: %w[rod staff robe hat accessory], innates: [],
                  levels: [ [ "haste", 1 ], [ "slow", 4 ], [ "dispel", 8 ], [ "reflect", 12 ], [ "mimic", 16 ], [ "gravity", 22 ], [ "stop", 28 ], [ "banish", 34 ],
                            [ "vanishing_act", 40 ], [ "time_lapse", 50 ] ] },
      healer: { typed_attack: false, name: "Healer", base_type: "fairy", skills: %w[trail parley], field_ability: "field_dressing", signature: "triage", passive: "potency",
                desperation: "purge",
                description: "An apothecary with a bag of bottles. Mends HP, braces the party, draws out the powder-sickness, and makes every remedy work better.",
                stat_multipliers: { max_hp: 85, max_mp: 140, mag: 115, spr: 130, str: 65 },
                equip_categories: %w[staff robe hat accessory], innates: [ { stat: "mdef", percent: 20 } ],
                levels: [ [ "cure", 1 ], [ "draw_out", 4 ], [ "regen", 8 ], [ "purify", 12 ], [ "bulwark", 16 ], [ "raise", 22 ], [ "reraise", 30 ],
                          [ "mass_cure", 38 ], [ "full_recovery", 50 ] ] },
      ranger: { name: "Ranger", base_type: "flying", skills: %w[trail draw], field_ability: "scout", signature: "call_hawk", passive: "first_strike",
                desperation: "rain_of_lead",
                description: "A long gun or a bow, a hawk overhead and a hound at heel. Hits what's out of reach, and never alone.",
                stat_multipliers: { max_hp: 105, str: 115, agi: 120, mag: 60 },
                equip_categories: %w[bow gun light_armor hat accessory], innates: [ { stat: "atk", add: 3 } ],
                levels: [ [ "aimed_shot", 1 ], [ "long_shot", 6 ], [ "volley", 12 ], [ "call_hound", 18 ], [ "pinning_shot", 24 ], [ "hunters_mark", 30 ],
                          [ "deadeye", 40 ] ] },
      soldier: { name: "Soldier", base_type: "normal", skills: %w[brawn trail], field_ability: "kick_it_in", signature: "pike_thrust", passive: "counter",
                 desperation: "forlorn_hope",
                 description: "Pike, matchlock and plate, and a lifetime of holding the line. Nothing clever; nothing that needs to be.",
                 stat_multipliers: { max_hp: 125, str: 115, vit: 115, agi: 90, mag: 50 },
                 equip_categories: %w[spear sword gun light_armor heavy_armor helmet hat accessory], innates: [ { stat: "atk", add: 6 } ],
                 levels: [ [ "pike_thrust", 1 ], [ "war_cry", 4 ], [ "halberd_sweep", 10 ], [ "butt_stroke", 16 ], [ "rally", 22 ], [ "fire_at_will", 32 ] ] },
      bodyguard: { name: "Bodyguard", base_type: "steel", skills: %w[nerve brawn], field_ability: "escort", signature: "guard", passive: "guardian",
                   desperation: "last_stand",
                   description: "Shield, plate and a promise. Steps in front of the blow meant for someone else, every time, and wears the heaviest of everything.",
                   stat_multipliers: { max_hp: 150, vit: 140, str: 100, spr: 110, agi: 75, mag: 40 },
                   equip_categories: %w[sword knife shield light_armor heavy_armor helmet hat accessory], innates: [ { stat: "def", percent: 20 } ],
                   levels: [ [ "guard", 1 ], [ "brace", 4 ], [ "shield_bash", 8 ], [ "interpose", 14 ], [ "shield_wall", 22 ], [ "unbreakable", 34 ] ] }
    }.merge(mancer_jobs).freeze
  end
end
