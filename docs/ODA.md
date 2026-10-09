# Oda — Archetypes Handoff

Oda is the third seeded setting (`db/seeds/oda/`), and the home of its archetypes, duels and masks. This document says what each archetype is, what it does, and which part of the engine does it. `docs/HANDOFF.md` still governs: the closed vocabularies stay closed, and everything here was added because an Oda archetype needed it.

## 1. The world

- **Oda** is a world of its own, not Earth's cultures renamed. Early modern material culture (16th century or so): matchlocks, clockwork, printing, river trade. Its genres are JRPG, tokusatsu, samurai films and westerns.
- **The tone swaps.** One session a grim frontier, the next a bright one with a masked hero and a monster of the week. That's the GM's to steer.
- **Powder** is its magic: elemental salts ground from crystal seams, fired through rods, staves and barrels. A gun is a cheap, dumb caster. MP is called Powder.
- **Types** (`worlds.damage_types`): Steel (the plain one), Shot (through armour), five powders round a circle (water quenches fire, fire burns wind, wind wears down earth, earth grounds thunder, thunder boils water), and Deep, what the giants are made of: steel and shot glance off it, and it breaks both.
- **Same type** is on (`Battle::RULES` `same_type`): a move of one of the user's own types is half again as strong.
- **The law.** Whoever refuses a duel is a coward, and a coward has no place in this world (§4).
- **Masks** are rare treasure (§5). **Giants** wake when a seam is dug too deep.
- **The atlas.** Noonbell, where every campaign starts, under the bell that rings for duels. Saltpeter, the powder town. Gearhold, the clock town, and the mask-maker's workshop behind it. Mines, forts and a drowned belfry. The cast: Silas Crane (the Smiling Draw, a duellist), Marrow Vey (who woke the giants), Mother Quill (who made the masks), and a bought sheriff.

## 2. The archetypes

The code says `Job`; screens say archetype. Each has its type, skills, field ability, signature, passive, desperation move, learn table, payoff, and a duel technique (`jobs.technique`).

| Archetype | Type | Signature | Passive | In a duel | Payoff |
| --- | --- | --- | --- | --- | --- |
| Courtsword | Steel | Sheathe | Second Wind | Wait | money |
| Firemancer … Windmancer | their powder | its Load | Clear Mind (mp_regen) | Opening | ABP |
| Thief | Wind | Mug | First Strike | Read | money |
| Monk | Earth | Palm Strike | Counter | Unbroken (tie_win) | EXP |
| Magician | Thunder | Quick | Clear Mind | Sleight (switch) | money |
| Healer | Water | Triage | Potency | Steady breath (recover) | a rumour |
| Ranger | Shot | Call Hawk | First Strike | Steady aim (steady) | money |

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
| `transform`, the `masked` and `spent` statuses | `Battle::Masks` | masks |
| the duel | `Battle::Duel` | everyone |

The property specs (`spec/battle/properties_spec.rb`) run all of it, and `spec/battle/oda_spec.rb` checks each piece.

## 4. Duels

- **The rules:** two people, to KO. Anyone can refuse. Whoever does is a **coward** until they fight another duel and win it.
- **A battle kind of its own** (`battles.kind`, state `"kind" => "duel"`): one party unit, one enemy, no items, no allies, no running.
- **Stances.** Each exchange both pick one: Strike beats Feint, Guard beats Strike, Feint beats Guard. They are shown together.
  - The winner lands a heavy blow.
  - Two Strikes trade light ones.
  - A matching Guard or Feint circles.
  - Stats and archetype set how hard a blow lands, never who wins the exchange.
- **Tells.** The opponent's next stance is drawn when the last exchange ends, with a tell: a line that gives it away three times in four, and bluffs otherwise. A Bestiary entry has its own lines (`monsters.tells`); without them it says the game's. The drawn stance waits in the state and the views never show it.
- **Techniques** (`Battle::Duel::TECHNIQUES`; a job's or a monster's `technique`):
  - **Wait** (Courtsword), chosen: hold an exchange; the next one won lands three times as hard.
  - **Opening** (Mancers): a shot before the first stare.
  - **Read** (Thief), chosen: the planned stance, plainly, without spending the exchange.
  - **Tie_win** (Monk): the first tie is a win.
  - **Switch** (Magician): the first exchange it would lose, it ties.
  - **Recover** (Healer): a little HP after every exchange.
  - **Steady** (Ranger): the first Strike that loses still lands lightly.
- **At the table** (`Campaign::Duels`):
  - **Fight control:** under the battle setup, the GM picks who and against whom: a cast member who fights as a Bestiary entry, or the entry itself. Then either "They challenge" (the challenged player answers on their screen) or "The challenge is taken" (the duel starts now).
  - **The Now strip** shows a waiting challenge. The GM can withdraw it.
  - **The duel's panel** is three stance rows, with Wait or Read for those who have them.

### 4.1 Cowards

A character's `coward` flag, seen by everyone (the party panel's struck-through tag, the sheet), with its costs:

- No mask will have them (`Battle::Masks`), and they find no desperation move.
- No payoff at a rest: nobody hires a coward.
- While one travels with the party, every town charges 25% more (`Location::Town#price_here`).
- Story lines can ask about it: the facts `cowards` (how many) and `coward` (who).

Winning a duel clears the flag (`BattleRecord::Settlement`), and the table hears it.

## 5. Masks

- **In the Armory:** items of category `mask`, worn as an accessory by anyone. Each has its own type, turns and moves (`items.mask`). Oda has six: Storm, Ember Fox, Tide, Stone, Gale and the Hollow Mask.
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

## 7. Settled while building

These were open questions in the first draft. Each was settled with the recommendation, and any of them can change:

1. **The duel's core:** stances, not the archetype's usual moves.
2. **Who duels:** anyone the GM plays as a Bestiary entry (a cast member, or the entry itself). Monsters can be called out, but only people can challenge a character.
3. **A coward can call someone out,** like anyone: it's their way back. A character's own challenge ("the challenge is taken") is the GM's to start.
4. **Refusing twice** changes nothing: coward is on or off.
5. **Powder** is the magic.
6. **Mancers:** one per powder, written from one form.
7. **Fire's rider** is a status of its own: burn.
8. **The Monk** banks chi rather than chaining forms.
9. **The Ranger** has a hawk that stays and a hound for three turns.
10. **Masks** are one of each per campaign by custom: nothing stops a GM from granting a second.

## 8. Not done

- **Steal tiers** (common, uncommon, rare): drop tables are already weighted, so they weren't needed.
- **Mix** (two items into one).
- **A giant's second phase** (growing on the field).
- **Rumour-travelling shame:** a coward is known everywhere at once, not town by town.
