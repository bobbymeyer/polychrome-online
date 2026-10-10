# Oda — Archetypes Handoff

Oda is the third seeded setting (`db/seeds/oda/`), and the home of its archetypes, duels and masks. This document says what each archetype is, what it does, and which part of the engine does it. `docs/HANDOFF.md` still governs: the closed vocabularies stay closed, and everything here was added because an Oda archetype needed it.

## 1. The world

- **Oda** is a world of its own, not Earth's cultures renamed. Early modern material culture (16th century or so): matchlocks, clockwork, printing, river trade. Its genres are JRPG, tokusatsu, samurai films and westerns.
- **The tone swaps.** One session a grim frontier, the next a bright one with a masked hero and a monster of the week. That's the GM's to steer.
- **Powder** is its magic: elemental salts ground from crystal seams, fired through rods, staves and barrels. A gun is a cheap, dumb caster. MP is called Powder.
- **Types** (`worlds.damage_types`): Steel (the plain one), Shot (through armour), five powders round a circle (water quenches fire, fire burns wind, wind wears down earth, earth grounds thunder, thunder boils water), and Deep, what the giants are made of: steel and shot glance off it, and it breaks both.
- **Same type** is on (`Battle::RULES` `same_type`): a move of one of the user's own types is half again as strong.
- **The law.** Whoever refuses a duel is a coward, and a coward has no place in this world (§4).
- **Masks** belong to one campaign, Dead Calm: there are seven, and that's all (§5, §9). **Giants** wake when a seam is dug too deep.
- **The atlas.** Noonbell, where every campaign starts, under the bell that rings for duels. Saltpeter, the powder town. Gearhold, the clock town. Mines, forts and a drowned belfry. The cast: Silas Crane (the Smiling Draw, a duellist), Marrow Vey (who woke the giants), and a bought sheriff.

## 2. The archetypes

The code says `Job`; screens say archetype. Each has its type, skills, field ability, signature, passive, desperation move, learn table and payoff.

| Archetype | Type | Signature | Passive | Payoff |
| --- | --- | --- | --- | --- |
| Courtsword | Steel | Sheathe | Second Wind | money |
| Firemancer … Windmancer | their powder | its Load | Clear Mind (mp_regen) | ABP |
| Thief | Wind | Mug | First Strike | money |
| Monk | Earth | Palm Strike | Counter | EXP |
| Magician | Thunder | Quick | Clear Mind | money |
| Healer | Water | Triage | Potency | a rumour |
| Ranger | Shot | Call Hawk | First Strike | money |
| Soldier | Steel | Pike Thrust | Counter | money |
| Bodyguard | Earth | Guard | Guardian | money |

### 2.1 Courtsword

A calm figure who waits, and draws last, and everyone else falls.

- **Sheathe** puts a stack of *sheathed* on them (`gather`). Stacks don't count down; they wait. **Stillwater** gathers two.
- **Draw** and **Final Draw** cut every enemy. They gain `boost`% for each stack of sheathed (`with`), and spend the stacks. They also gain `patience`% for everyone who went first this round, so a slow Courtsword is a strong one.
- **Iai Stance** (status `iai`): the first opponent to aim a physical blow at them alone is cut down before it lands.
- **Zantetsuken** is three times as hard against the `wounded` (at 30% HP or less).
- **Last Light** spends every stack on one cut.

### 2.2 The Mancers

Five archetypes from one form (`MANCER_POWDERS`), one per powder: Firemancer, Watermancer, Thundermancer, Earthmancer, Windmancer.

- **Four measures:** Fire, Fira (all enemies), Firaga, Firaja (and Water…, Thunder…, Stone…, Aero…).
- **The top measure** is `unresisted`: a resistance counts as neutral. It also `reload`s, so the caster loses their next turn.
- **A trick per powder:**
  - Scorch: burn.
  - Undertow: slow.
  - Jolt: paralyze.
  - Stoneskin: a barrier on an ally.
  - Gale: blows the target off the field.
- **A Load** (`imbue`) gives an ally's weapon the powder. A specialist with a bad matchup changes the matchup instead.
- **A field art per powder.**

### 2.3 Thief

- **Mug** and **Steal** take a drop.
- **Lift** steals a good status instead (`steal` with `boon`): haste, a barrier, reflect, a charge.
- **Also:** Blinding Dust, Backstab (heavy against the blind), Hide, Shadowstep, Grand Larceny.
- **Pick Lock** (field ability) has the `unlock` outcome: the lock in the party's way in a dungeon opens without its key.
- **Pickpocketing** is a check the GM calls with an outcome on a success (money) and one if everyone fails: `disgrace`. Caught, the town where it happened thinks worse of the party (a deed with negative sway), so its prices go up.

### 2.4 Monk

Gave up powder: no Monk ability costs MP.

- **Palm Strike** and **Iron Body** gather *chi*; **Gather Breath** gathers two.
- **Dragon Fist** and **Seven Forms** spend every stack (`with: chi`) and `pierce` armour (part of the target's defence counts for nothing).
- **Also:** Chakra, Revenge (grudge), Hundred Fists.

### 2.5 Magician

Control, not damage.

- **Quick:** an ally goes again at once, once a round.
- **Mimic:** the last move an ally made, again, free.
- **Dispel** strips an enemy's good statuses and raised stats.
- **Reflect:** single-target magic turns back on its caster.
- **Also:** Haste, Slow, Gravity, Stop, Banish, Vanishing Act, Time Lapse.

### 2.6 Healer

- **Triage** heals more the lower the target (`triage`).
- **Regen** and **Reraise** are statuses given to others. Reraise gets its wearer up once when knocked out.
- **Also:** Draw Out (powder-sickness and burns), Purify, Bulwark, Raise, Mass Cure.
- **Potency** (passive): items in their hands work half again as well.

### 2.7 Ranger

- **Reach.** Shots find targets off the field: leaping, hiding, sent away. These are Aimed Shot, Long Shot, Volley, Pinning Shot and Deadeye.
- **Long Shot** is big, and reloads.
- **Call Hawk** brings a companion that `stays` the whole battle; **Call Hound** brings one for three turns.
- **Typed shot** (fire, thunder, water, stone, wind) is ammunition in the Armory that anyone can fire.

### 2.8 Soldier

Pike, matchlock and plate. The straight heavy fighter.

- **Wears** spears, swords and guns, heavy armour and helmets. No shield: a pike takes both hands.
- **Pike Thrust** goes through part of the target's defence (`pierce`).
- **Halberd Sweep** cuts the whole line, and **Fire at Will** is three shots at random.
- **War Cry** strengthens the Soldier; **Rally** strengthens the party.
- **Butt Stroke** can stun (paralyze).
- **Kick It In** (field ability) has the `unlock` outcome, on Brawn: the Thief's pick, with a boot.
- **Forlorn Hope** is their desperation move: a charge on everyone, harder the more hurt they are.

### 2.9 Bodyguard

The tank: in front of the blow meant for someone else, and in the heaviest of everything.

- **Wears** the most defence there is: heavy armour, helmets, and the only shields in Oda. Swords or knives. Defence +20%, and the most HP of anyone.
- **Guardian** (passive, FF5's Cover): a single blow meant for a badly hurt ally (30% HP or less) comes to the Bodyguard instead, if they're in better shape and free to move.
- **Guard** (`cover` status) takes every single blow meant for the party, for three turns.
- **Brace** raises their own defences, **Interpose** shields an ally, **Shield Wall** raises the party's defence, and **Unbreakable** gives regen and a great deal of defence.
- **Shield Bash** can stun.
- **Escort** (field ability) has the `safe_road` outcome, on Nerve.
- **Last Stand** is their desperation move: everything they've taken, given back at once.

The **Courtsword** wears heavy armour too.

## 3. The engine, piece by piece

| Piece | Where | Who it's for |
| --- | --- | --- |
| Stacking statuses (`sheathed`, `chi`), `gather`, `with`/`boost`/`hold` | `Battle::Effects#gather`, `Resolver#fortify` | Courtsword, Monk |
| `patience` | `Resolver#fortify` (`Context#acted`) | Courtsword |
| `wounded`, `giant` (`AGAINST_TRAITS`) | `Effects#against`, `Effects#typed` | Courtsword, Ranger, masks |
| `pierce`, `unresisted` | `Effects#pierced`, `Effects#typed` | Monk, Mancers |
| `same_type` rule | `Effects#typed` | Mancers (every archetype, in Oda) |
| `reload` on an ability, the `reloading` status | `Resolver#reload` | Mancers, Ranger |
| `reach` on an ability | `State.target_problem`, `Context#opponents` | Ranger |
| `dispel`, `quick`, `mimic` | `Effects`, `Resolver#follow_up` | Magician |
| `reflect`, `iai`, `regen`, `reraise`, `burn` | `Resolver#reflected`, `#iai`, `Effects#upkeep`, `Context#reraised` | Magician, Courtsword, Healer, Firemancer |
| `steal` with `boon` | `Effects#steal_boon` | Thief |
| `triage`, `potency` | `Effects#heal`, `#revive` | Healer |
| `summon` with `stays` | `Resolver#count_down_summon` | Ranger |
| the `guardian` passive | `Resolver#covered` | Bodyguard |
| `transform`, the `masked` and `spent` statuses | `Battle::Masks` | masks |

The property specs (`spec/battle/properties_spec.rb`) run all of it, and `spec/battle/oda_spec.rb` checks each piece.

## 4. Duels

A duel is not a battle. It's a scene of its own at the table (`Duel`, scored by the pure `DuelMeter`), and neither HP nor archetype has any part in it.

- **The rules:** two people, one against one. Anyone can refuse; whoever does is a **coward** until they fight another duel and win it.
- **The meter.** Each duellist has their own, at the same target:
  - **Swing** starts the needle across it and back; the next press stops it.
  - **The challenged player** swings their character's. **The GM** swings the opponent's: they play them.
- **Scoring:**
  - a 1-unit **perfect** line in the middle, 3 points;
  - **good** either side of it, 2;
  - **okay** beyond that, 1;
  - anywhere else a **miss**, 0.
- **Three rounds.** Each round the target moves (drawn from the duel's seed) and its bands narrow: good reaches 5, 4, then 3 units beyond the perfect line, okay 10, 7, then 4 beyond good. The meter is 300 units long, scaled to the screen.
- **Hidden swings.** Nobody sees a swing until both are in. Then the round's grades go on the scorecard and into the log.
- **The result.** After three rounds:
  - **The higher total wins.** A character who loses is left knocked out.
  - **Level totals read SATISFACTION,** and both win.
  - **Winning, or satisfaction,** ends a coward's shame.
- **At the table** (`Campaign::Duels`):
  - **Fight control:** under the battle setup, the GM picks who and against whom: a cast member who fights as a Bestiary entry, or the entry itself. Then either "They challenge" (the challenged player answers Accept or Refuse on their screen) or "The challenge is taken" (the duel starts now).
  - **While it's on,** the duel is the table's Now: both meters, the round, the scorecard.
  - **When it ends,** the result is in large type until the GM puts it away.

### 4.1 Cowards

A character's `coward` flag, seen by everyone (the party panel's struck-through tag, the sheet), with its costs:

- No mask will have them (`Battle::Masks`), and they find no desperation move.
- No payoff at a rest: nobody hires a coward.
- While one travels with the party, every town charges 25% more (`Location::Town#price_here`).
- Story lines can ask about it: the facts `cowards` (how many) and `coward` (who).

Winning a duel, or satisfaction, clears the flag (`Duel`), and the table hears it.

## 5. Masks

- **In the Armory:** items of category `mask`, worn as an accessory by anyone. Each has its own type, turns and moves (`items.mask`). There are seven, all Dead Calm's (§9): Red, Orange, Yellow, Green, Indigo, Blue and Violet. Oda's own books have none, and its atlas, cast, tables and codex never mention them.
- **Never sold:** found as treasure, or given by the GM.
- **Its Don.** Wearing one puts **Don the … Mask** on the menu (`Item#don_ability`).
- **Putting it on** (`transform`), for its turns, the wearer gains:
  - stats up (`masked`),
  - their Attack striking with the mask's type,
  - the mask's moves on their menu,
  - the mask's art on the board.
- **Afterwards** they're *spent* for two turns.
- **Against giants,** a masked blow lands twice as hard.
- **A coward** can't put one on.

## 6. Dungeons: locks and traps

- **Locks and their keys** were already in the generator. A lock now also opens to the `unlock` outcome: a Thief's Pick Lock, or a check the GM calls with it.
- **Traps are a room's decision** (`Generators::Dungeon`; a template weighs `trap`, and a `traps` generator table lists them).
  - A trap is written like a fork's cost: "A tripwire and a powder charge. (hurt 20)".
  - It waits in its room until the GM has someone disarm it (a check) or lets it go off.
  - Walking on past it sets it off.
  - On the floorplan it is an amber triangle.
- **A fight bars the way on.** Ways on from a room deeper in stay shut while its fight is still waiting (`Location::Exploration#barred_by`).
  - An encounter opens them when it's won or the GM waves it off. The master's room opens them only when it's won.
  - The way back always stays open.
  - The table's ways on leave a barred way out and name it, as they do a locked door.

## 7. Settled while building

1. **The duel** is outside battle: a meter, three rounds, a score (Bobby's design). Ties are SATISFACTION and both win. There is no kill.
2. **Who duels:** anyone the GM plays, as a cast member or a Bestiary entry. The GM swings their meter.
3. **A coward can call someone out,** like anyone: it's their way back. A character's own challenge ("the challenge is taken") is the GM's to start.
4. **Refusing twice** changes nothing: coward is on or off.
5. **Powder** is the magic.
6. **Mancers:** one per powder, written from one form.
7. **Fire's rider** is a status of its own: burn.
8. **The Monk** banks chi rather than chaining forms.
9. **The Ranger** has a hawk that stays and a hound for three turns.
10. **Masks** are Dead Calm's seven, each worn by a guardian and dropped when it falls. They live in Oda's Armory, because items are a world's, but nothing else in Oda hands them out.

## 8. Not done

- **Steal tiers** (common, uncommon, rare): drop tables are already weighted, so they weren't needed.
- **Mix** (two items into one).
- **A giant's second phase** (growing on the field).
- **Rumour-travelling shame:** a coward is known everywhere at once, not town by town.

## 9. Dead Calm, a written campaign

`db/seeds/campaigns/dead_calm.rb` is Bobby's kaiju-mecha campaign, started for a GM with `bin/rails "campaigns:seed[dead_calm,gm@example.com]"`. It makes a campaign in Oda from a blank map, since the island is cut off from the mainland. Run again, it finds that GM's campaign rather than making another.

- **Oda's books gain** (only what's missing):
  - each guardian and its forms;
  - the mooks and duellists;
  - the seven plain masks;
  - a five-room dungeon template.
- **The island's map** has the city's tiers laid out as she lies under them. Each dungeon is rolled as one corridor, and its rooms are pinned to the entrance, puzzle, setback and guardian. The twist is a room past the guardian.
- **The rest of the campaign:**
  - the cast;
  - the Seven Signs and the Torso's siege, as clocks;
  - the founding secrets, as chains of clues;
  - the scenes, from the cold open to the seven mask visions;
  - the GM's checklist, as flags.
- **The notes' types are mapped onto Oda's.** Rock and Ground are Earth, Bug and Flying are Wind, Normal is Steel, Poison/Grass is Earth with a poison bite, and Ghost/Steel is Steel.
- **Some of the notes' patterns are the GM's to play**, because the engine doesn't do them:
  - striking first on a riposte;
  - "whoever hit it last";
  - interrupting a telegraph;
  - freeing a grabbed ally.

  Each dungeon's GM notes say which.
- **The island has its own voice.** The Steps is an Island city, with its own people, shops and buildings. Dead Calm's arrival lines and GM moves are in Oda's tables but ask for the campaign's `dead_calm` and `island` flags, so they fit no other campaign and beat Oda's mesa lines on the island.
- **The Giant Battle is not built.**
