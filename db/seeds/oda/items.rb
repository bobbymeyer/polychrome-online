# frozen_string_literal: true

# The Outfitter: remedies, powder shot, and each kind of gear in three
# steps. Oda has no masks of its own: there are seven, and they are Dead
# Calm's (db/seeds/campaigns/dead_calm). (Seeds::Oda)
module Seeds
  module Oda
    ITEMS = {
      # --- remedies: an Apothecary makes them work half again as well (potency) -----------
      tonic: { name: "Tonic", category: "consumable", price: 40, target: "single_ally",
               effects: [ { primitive: "heal", power: 30 } ], description: "Bitter, brown, and it works." },
      strong_tonic: { name: "Strong Tonic", category: "consumable", price: 150, target: "single_ally",
                      effects: [ { primitive: "heal", power: 80 } ], description: "Twice as bitter. Twice as good." },
      smelling_salts: { name: "Smelling Salts", category: "consumable", price: 300, target: "single_ally",
                        effects: [ { primitive: "revive", fraction: 20 } ], description: "Under the nose, and they're back, swearing." },
      charcoal_draught: { name: "Charcoal Draught", category: "consumable", price: 50, target: "single_ally",
                          effects: [ { primitive: "cleanse", kind: "poison" }, { primitive: "cleanse", kind: "burn" } ],
                          description: "Black, gritty, and the only cure for powder-sickness anyone trusts." },
      eyewash: { name: "Eyewash", category: "consumable", price: 50, target: "single_ally",
                 effects: [ { primitive: "cleanse", kind: "blind" } ], description: "For dust, smoke and a Thief's pepper." },
      panacea: { name: "Panacea", category: "consumable", price: 250, target: "single_ally",
                 effects: [ { primitive: "cleanse" } ], description: "An Apothecary's best bottle. Cures everything but being down." },
      smoke_pot: { name: "Smoke Pot", category: "consumable", price: 80, target: "self",
                   effects: [ { primitive: "escape" } ], description: "Grey powder and a fuse. For a bad plan." },
      # Shot: a Ranger's ammunition, loaded with a powder (anyone can fire it).
      fire_shot: { name: "Fire Shot", category: "consumable", price: 90, target: "single_enemy",
                   effects: [ { primitive: "elemental", type: "fire", power: 30 } ], description: "A cartridge of red salt. Lights whatever it hits." },
      thunder_shot: { name: "Thunder Shot", category: "consumable", price: 90, target: "single_enemy",
                      effects: [ { primitive: "elemental", type: "thunder", power: 30 } ], description: "Yellow salt. Makes the hair stand up on the way out." },
      water_shot: { name: "Water Shot", category: "consumable", price: 90, target: "single_enemy",
                    effects: [ { primitive: "elemental", type: "water", power: 30 } ], description: "Blue salt. Puts out a fire, or a fire-eater." },
      stone_shot: { name: "Stone Shot", category: "consumable", price: 90, target: "single_enemy",
                    effects: [ { primitive: "elemental", type: "earth", power: 30 } ], description: "Grey salt, heavy as a fist." },
      wind_shot: { name: "Wind Shot", category: "consumable", price: 90, target: "single_enemy",
                   effects: [ { primitive: "elemental", type: "wind", power: 30 } ], description: "Green salt. It curves." },

      # --- gear: three steps of each kind. The first is what a new character starts in;
      # the second Noonbell and Saltpeter sell; the third Gearhold, or the Reach.
      short_blade: { name: "Short Blade", category: "sword", price: 200, stats: { atk: 14 }, description: "Plain steel, a plain grip. Honest." },
      court_blade: { name: "Court Blade", category: "sword", price: 600, stats: { atk: 22, agi: 2 }, description: "Long, curved, and very sharp. Wears its sheath like a coat." },
      noon_blade: { name: "Noon Blade", category: "sword", price: 1600, stats: { atk: 31, agi: 3 }, description: "Folded steel and a little powder in the temper. It rings at noon." },
      knife: { name: "Knife", category: "knife", price: 120, stats: { atk: 9, agi: 2 }, description: "For bread, ropes and emergencies." },
      stiletto: { name: "Stiletto", category: "knife", price: 500, stats: { atk: 16, agi: 4 }, description: "Thin enough to go between ribs, and between bars." },
      quay_knife: { name: "Quay Knife", category: "knife", price: 1400, stats: { atk: 24, agi: 6 }, description: "Saltpeter's best. Nobody asks where it came from." },
      powder_rod: { name: "Powder Rod", category: "rod", price: 180, stats: { atk: 4, mag: 4 }, description: "A brass tube for firing a measure true." },
      charge_rod: { name: "Charge Rod", category: "rod", price: 600, stats: { atk: 6, mag: 9 }, description: "Rifled inside. The powder spins and goes further." },
      seam_rod: { name: "Seam Rod", category: "rod", price: 1800, stats: { atk: 8, mag: 15 }, description: "Cut from a crystal seam and capped in silver." },
      walking_staff: { name: "Walking Staff", category: "staff", price: 160, stats: { atk: 6, mag: 3, spr: 2 }, description: "For mesas, and for leaning on." },
      healers_staff: { name: "Healer's Staff", category: "staff", price: 550, stats: { atk: 8, mag: 7, spr: 5 }, description: "Hung with little bottles that chime." },
      bell_staff: { name: "Bell Staff", category: "staff", price: 1500, stats: { atk: 10, mag: 12, spr: 8 }, description: "A Monk house's gift: a bell on top that never quite stops." },
      hunting_bow: { name: "Hunting Bow", category: "bow", price: 220, stats: { atk: 13, agi: 2 }, description: "Horn and sinew. Quiet." },
      mesa_bow: { name: "Mesa Bow", category: "bow", price: 650, stats: { atk: 21, agi: 3 }, description: "Recurved, for shooting from horseback." },
      matchlock: { name: "Matchlock", category: "gun", price: 300, stats: { atk: 17 }, description: "A slow match, a pan of powder and patience." },
      wheellock: { name: "Wheellock", category: "gun", price: 900, stats: { atk: 26 }, description: "A spring and a wheel instead of the match. Gearhold's pride." },
      long_rifle: { name: "Long Rifle", category: "gun", price: 2200, stats: { atk: 36 }, description: "Six feet of barrel. Reaches the next mesa." },
      pike: { name: "Pike", category: "spear", price: 250, stats: { atk: 16 }, description: "Eighteen feet of ash with a point on the end." },
      partisan: { name: "Partisan", category: "spear", price: 700, stats: { atk: 25 }, description: "A broad blade on a pole, and two wings to stop it going too deep." },
      halberd: { name: "Halberd", category: "spear", price: 1800, stats: { atk: 35 }, description: "Axe, spike and hook on one haft. Gearhold forges it for the town watch." },
      buckler: { name: "Buckler", category: "shield", price: 180, stats: { def: 5 }, description: "A fist-sized shield for turning a blade aside." },
      target_shield: { name: "Target", category: "shield", price: 550, stats: { def: 10, mdef: 2 }, description: "A round shield, iron-rimmed, its face painted with a house's colours." },
      pavise: { name: "Pavise", category: "shield", price: 1500, stats: { def: 16, mdef: 5 }, description: "A shield as tall as its bearer. Shot stops at it." },
      morion: { name: "Morion", category: "helmet", price: 150, stats: { def: 4 }, description: "A steel cap with a comb and a brim." },
      burgonet: { name: "Burgonet", category: "helmet", price: 500, stats: { def: 8, mdef: 2 }, description: "Cheek plates, a peak, and a crest for the bold." },
      close_helm: { name: "Close Helm", category: "helmet", price: 1400, stats: { def: 12, mdef: 4 }, description: "Shut all round. You see through a slit and hear your own breath." },
      cuirass: { name: "Cuirass", category: "heavy_armor", price: 400, stats: { def: 16 }, description: "A breastplate and a backplate, buckled together." },
      half_plate: { name: "Half Plate", category: "heavy_armor", price: 1100, stats: { def: 26 }, description: "Plate to the knee. A pikeman's harness." },
      gearhold_plate: { name: "Gearhold Plate", category: "heavy_armor", price: 2600, stats: { def: 36, mdef: 4 }, description: "Fluted, articulated, and proof against a pistol ball at ten paces." },
      travel_coat: { name: "Travel Coat", category: "light_armor", price: 150, stats: { def: 6 }, description: "Long, dusty, a lot of pockets." },
      duster: { name: "Duster", category: "light_armor", price: 500, stats: { def: 12, agi: 1 }, description: "Oiled canvas. Turns a knife, mostly." },
      brigandine: { name: "Brigandine", category: "light_armor", price: 1400, stats: { def: 20 }, description: "Plates sewn into a coat. Heavy on the shoulders." },
      monks_wrap: { name: "Monk's Wrap", category: "light_armor", price: 400, stats: { def: 9, agi: 2 }, description: "Linen bindings, worn a hundred years by someone." },
      robe: { name: "Robe", category: "robe", price: 140, stats: { def: 3, mdef: 6 }, description: "Plain, with powder burns on the cuffs." },
      mancers_robe: { name: "Mancer's Robe", category: "robe", price: 520, stats: { def: 5, mdef: 12, mag: 2 }, description: "Lined with salt-proof silk." },
      wide_hat: { name: "Wide Hat", category: "hat", price: 100, stats: { def: 2, mdef: 2 }, description: "Keeps the noon out of your eyes." },
      lacquered_hat: { name: "Lacquered Hat", category: "hat", price: 450, stats: { def: 5, mdef: 5 }, description: "Black lacquer, red cord. Turns rain and the odd blade." },
      powder_horn: { name: "Powder Horn", category: "accessory", price: 300, stats: { mag: 3 }, description: "A horn of good powder: every measure goes further." },
      lucky_mark: { name: "Lucky Mark", category: "accessory", price: 400, stats: { agi: 3 }, description: "A coin with a hole shot through it. Someone was lucky once." },
      iron_bracer: { name: "Iron Bracer", category: "accessory", price: 350, stats: { def: 5 }, description: "For catching a blade on the arm." }
    }.freeze
  end
end
