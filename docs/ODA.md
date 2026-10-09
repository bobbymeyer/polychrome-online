# Oda — Archetypes Handoff

The archetypes of Oda, the third seeded setting, and what the engine needs to play them. Written from a brainstorm, before any code. `docs/HANDOFF.md` still governs: the closed vocabularies stay closed, and a primitive, status or rule is added only when an Oda archetype needs it.

Each section says what is **decided** (Bobby said so), what is **proposed** (a recommendation, open to change) and what is **open**. Nothing proposed is built until it is decided.

## 1. The world, as far as the archetypes need it

Decided:

- **Oda** is a world of its own, not Earth's cultures renamed. Early modern material culture (16th century or so): matchlocks, clockwork, printing, sailing ships. Magic and technology blend.
- Its genres are JRPG, tokusatsu, samurai films and westerns. They shape the scenes the world makes, not who lives in it.
- **Tone swaps.** One session can be grim and the next goofy, so the story is never too dark or too silly. That's the GM's to steer.
- **Duels** (§4): between two people, to KO, a battle that plays differently. Refusing one makes you a coward.
- **Masks** (§5) are rare treasure.

Proposed:

- **Powder.** Magic is a measured substance ground from crystals: fire, water, thunder and the rest, packed into cartridges and paper charms and fired through barrels, staves and talismans. A gun is a cheap, dumb caster. Mining it is the frontier's business; dig too deep and things wake up (the tokusatsu monster, and the giants of §5).
- **Damage types** (the world's own, `worlds.damage_types`; the first is the plain one): **Steel**, Shot, Fire, Water, Thunder, Earth, Wind, and one uncanny type for the things that wake (Deep). One mancer per elemental type.

## 2. The archetypes

Seven, as Bobby named them. In-world names are a proposal; the code word is `Job`, the screens say archetype.

| Archetype | One line | Proposed in-world name |
| --- | --- | --- |
| Courtsword | Calm, waits, draws last, cuts everyone down | Courtsword |
| (Type)mancer | Deep in one element: Fire, Fira, Firaga | Firemancer, Watermancer, Thundermancer… |
| Thief | Steals, opens locks | Nighthand |
| Monk | Martial arts | Mendicant |
| Magician | Utility magic, more varied than the mancers, less damage | Artificer |
| Healer | HP, defence, poison | Apothecary |
| Ranger | Missiles, and animals | Outrider |

For each: what it's for, what it borrows, what the engine already has, what it needs, and its life outside battle (field ability and payoff, `Job#payoff`). Duel techniques are in §4.

### 2.1 Courtsword

**For:** the samurai-film moment. A calm figure does nothing visible, then draws at the last moment and everyone falls. The gunslinger's draw is the same beat. Dragon Quest rounds (everyone chooses, then everything goes in speed order) make "last" something the engine can mean.

**Borrows:** Bravely Default's Brave/Default (bank turns, spend them at once); FFT's Samurai, Draw Out; FF6 Cyan's Bushido (a technique that grows while you wait); Odin's Zantetsuken (finish anything below a line); Sekiro and Fire Emblem's Vantage (cut first when attacked).

**Has:** `charge` (up to three turns), the `charged` status (next move twice as strong), the `counter` passive.

**Needs:**

1. **Sheathe.** A status that grows each turn the Courtsword waits, spent on one strike at all enemies that scales with it. Statuses today have turns, not a count: this is the **stacking status** (§6), which the Monk and mancers use too.
2. **Patience.** More power for every unit that acted before it this round. A pure function of the round's order. It rewards a slow Courtsword for going last.
3. **Execute.** `wounded` as an `against` trait beside `undead` and `boss`: a bonus, or a sure KO, against a target under some share of its HP. The draw finishes what the round softened.
4. Later, perhaps: **Iai stance.** A reaction that strikes a single-target attacker before its blow lands. It interrupts resolution, so it's the most expensive of the four.

**Shape:** low Agi, high Str, fragile while waiting. The Knight's opposite.

**Outside battle (proposed):** field ability *stare down* (a check that makes someone back off). Payoff: money, from bodyguard work.

### 2.2 (Type)mancers

**For:** depth in one element. One mancer per elemental type, each climbing the same ladder: Fire, Fira, Firaga, Firaja. With powder, the tiers are a single, double and triple measure.

**Borrows:** Pokémon's same-type bonus; FFXIV Black Mage's alternating phases that build power; FF5's Spellblade (lend your element to an ally's weapon).

**Has:** `elemental`, tiered families in the Grimoire (one form, many tiers), `imbue`, a job's `base_type`, status riders on any move.

**The problem:** a specialist facing something that resists their element has nothing to do. Answers:

- The top tier **pierces resistance**: a resist counts as neutral.
- **Load an ally.** Imbue someone's weapon with your element: you change the matchup instead of dealing the damage.
- One rider per element from the existing statuses: Fire with damage over time, Water cleanses or slows, Thunder paralyzes, Earth shields, Wind knocks away (`away` on the target).

**Needs:**

1. **Same-type bonus** and **resist-pierce** as damage params.
2. **Reload** (§6): a big shot leaves the caster spent for a turn.
3. **A burn.** World words rename a status everywhere, so Fire's damage over time can't be called burn while poison is still poison. Either Fire's rider *is* poison, worded for it, or burn is its own status. Open.
4. **Mancers from the types.** One mancer per elemental type, written from one form, the way the Grimoire writes tiers. Proposed, not decided: Oda could as easily have three hand-written mancers.

**Outside battle (proposed):** one field ability per element: light or burn, douse, power a mechanism, move earth, carry a sound. Payoff: ABP, from study.

### 2.3 Thief

**For:** stealing and locks.

**Borrows:** FF9's steal tiers (common, uncommon, rare); FFT's Steal Gil and Steal Heart; FFXII's stolen buffs; Octopath Traveler's Therion (steals from people, opens what only a thief can).

**Has:** `steal` (once per target), Mug, Hide and Smoke Bomb (`away`), `first_strike`, and *pick lock* as a field ability.

**Needs:**

1. **Steal a buff.** Take the target's haste or shield for yourself. A `steal` param or a small primitive.
2. **Locks in dungeons.** HANDOFF §7 says "lock/key later". The Thief is why later is now: a locked room is a decision (spend the key, or let the Thief try), and every room must carry one. Clockwork locks suit Oda.
3. **Traps.** Find and disarm, as a room decision.
4. **Picking pockets in town.** Caught, the party's sway in that town drops, through deeds. Proposed.

**Outside battle:** *pick lock* (has). Payoff: money.

### 2.4 Monk

**For:** martial arts. With powder, the Monk is the one who gave it up: no ability of theirs spends it (proposed).

**Borrows:** FFXIV Monk's forms (each move sets up the next); FF6 Sabin's Blitz; a chi meter that blows build and finishers spend; pressure points that ignore defence.

**Has:** Kick, Focus, Chakra, Revenge (`grudge`), Hundred Fists, `counter`, moves that cost HP.

**Needs:**

1. **`with`:** a bonus when the *user* has a status, optionally spending it. The mirror of `against`, which already does this for the target's status. This makes forms and chains possible.
2. **Chi** as a stacking status (§6), if the Monk banks rather than chains. Open.
3. **Ignore defence** as a physical param.

**Outside battle:** *meditate* (has). Payoff: EXP, from training.

### 2.5 Magician

**For:** utility. More varied than the mancers, less damage. Kept distinct from a generalist with a sword by being the archetype of **control**: time, mirrors, smoke, small machines.

**Borrows:** FF5's Time Mage (Haste, Slow, Stop, Float, Gravity, Quick, Teleport); FF5's Mime (do an ally's last move again); Dispel, Reflect, Banish.

**Has:** haste, slow and stop; `percent` (Gravity); `away` on the target (Banish); blind, confuse, silence; the resolver already repeats moves (haste, One More).

**Needs:**

1. **Dispel.** `cleanse` today only cures harmful statuses; this takes good ones off an enemy.
2. **Reflect.** A status that turns single-target magic back. The natural answer to an enemy mancer.
3. **Quick.** An ally goes again now (`extra_go` exists).
4. **Mimic.** Do the last move an ally made.

**Outside battle (proposed):** the best field archetype. Light, illusion, mend a machine, appraise, Teleport between towns already visited (the `safe_road` and `sneak` outcomes). Payoff: money, from repairs.

### 2.6 Healer

**For:** HP, defence, poison. The physician with a bag rather than the priest with a prayer.

**Borrows:** FFXIV Scholar (shields and healing over time: prevention over cure); FF5 and FFT's Chemist (items work better in their hands; Mix); triage (heals more the lower the target); Reraise.

**Has:** `heal`, `revive`, `cleanse`, `shield`, buffs to def and mdef, the `regen` passive.

**Needs:**

1. **Regen as a status,** given to someone else. Today it's only a passive.
2. **Reraise.** A status that gets its wearer back up once when knocked out: `second_wind`, given.
3. **Item potency.** Items used by a Healer are stronger.
4. Later: **Mix,** two items into one effect.

**Outside battle (proposed):** cure a town's sickness: a place in a "fever" mode, shut services and all, that the Healer can end. Better rests. Payoff: money, from remedies.

### 2.7 Ranger

**For:** missiles and animals. A long gun or a bow; a hawk or a hound.

**Borrows:** FF5's Ranger (Animals calls a random creature by level; Rapid Fire hits random enemies; Aim); FFT's Archer (charge for a surer shot); companion animals from D&D and WoW.

**Has:** `random_enemy` with several hits (Rapid Fire), `summon` (small creatures from the Bestiary, up to five turns), `charge`, typed physical damage.

**Needs:**

1. **Reach.** Shots hit what's out of reach (`airborne`, and perhaps `away`). Without rows, this and a low profile are what range means.
2. **Ammunition** as items: fire shot is a typed strike. Pairs with the mancers.
3. **Reload** (§6), for the long gun.
4. **Animals,** as distinct from a summoner's: free or cheap, random by level as in FF5. A **companion** that stays the whole battle is the strongest version and the most expensive: a unit tied to its owner. Open.

**Outside battle:** track, hunt, scout. Payoff: money, from pelts.

## 3. Proposed per-archetype summary

| Archetype | Key new mechanic | Field ability | Payoff |
| --- | --- | --- | --- |
| Courtsword | Sheathe, Patience, Execute | stare down | money |
| Mancer | Same-type bonus, resist-pierce, load an ally | one per element | ABP |
| Thief | Steal a buff; locks and traps | pick lock | money |
| Monk | `with` (forms), ignore defence | meditate | EXP |
| Magician | Dispel, Reflect, Quick, Mimic | many | money |
| Healer | Regen and Reraise as statuses, item potency | field dressing | money |
| Ranger | Reach, ammunition, reload, animals | scout | money |

## 4. Duels

Decided:

- A duel is between **two people**, to **KO**.
- It is **a different kind of battle** in the engine, not a regular battle with one unit a side. The details are to be worked out.
- Anyone may **refuse.** Whoever refuses becomes a **coward** (§4.2).
- A coward stops being one only by **fighting and winning another duel.**
- There is no further duel law: no courts, champions, witnesses, writs or verdicts.

### 4.1 The battle (proposed)

A duel is a mind game, not a contest of totals. If it were a regular battle, the stronger character would simply win.

**Borrows:** Suikoden's duels (each exchange, both pick Attack, Defend or Desperate in secret, and the opponent's line beforehand is a tell); Bushido Blade (few exchanges, a clean hit decides); the western standoff (stillness, then the draw: initiative is chosen, not Agi); Yomi (read the opponent).

- **The stare.** Each exchange, both choose a stance in secret. Choices are revealed together.
- **Three stances:**

  | Stance | Beats | Loses to |
  | --- | --- | --- |
  | Strike | Feint | Guard |
  | Guard | Strike | Feint |
  | Feint | Guard | Strike |

  The winner of an exchange lands a heavy blow; a tie trades light ones. Stats and archetype set how hard, not who wins.
- **Tells.** A line from the opponent before each exchange: the GM speaks it, or the monster's AI script supplies it. Players read the GM, and the GM reads the players.
- **One technique per archetype,** so it isn't only rock-paper-scissors:
  - **Courtsword:** waits an exchange on purpose; if it wins the next, that's the KO.
  - **Mancer:** a shot before the first stare.
  - **Thief:** sees one tell plainly.
  - **Monk:** a tie counts as a win, once.
  - **Magician:** changes stance after the reveal, once.
  - **Healer:** recovers between exchanges.
  - **Ranger:** wins ties.
- **No items, no allies, no fleeing.** Fleeing is refusing. A mask may be worn (§5).

**In the engine:** a battle **kind** in the state (`duel`). A resolver path that takes two hidden inputs and resolves them as a pair. New events for the player (`stare`, `tell`, `reveal`, `clash`). It replays exactly like any battle (HANDOFF §5). Inputs are already collected before a round resolves; what's new is that neither side sees the other's choice until both are in.

### 4.2 The coward

A coward is **a character's** state, seen by everyone, not a campaign `flag` (those are the GM's own notes and never shown to players).

Proposed effects, through systems that exist:

- **Word travels as a rumour.** The place where they refused knows at once; every other place learns when the rumour reaches it, a road a day (`Pointcrawl::Overnight`). A coward can outrun their shame for a while.
- **Towns treat them worse** once they know: dearer prices, or no service at all. Sway today belongs to the party, so this needs a per-character version.
- **No archetype payoff at rest.** Nobody hires a coward.
- **Masks refuse a coward** (§5).
- **Challengers seek them out.** A coward is easy prey, so the GM has more duels to offer, which is also the way back.
- **A small mark in battle,** such as no desperation move. Small, so a cowardly player still enjoys the table.

Clearing it: win a duel. The coward state lifts, and the win is a deed whose rumour travels like the shame did.

## 5. Masks

Decided: masks are **rare treasure.**

Proposed:

- **Unique and named.** Each mask exists once in the world; a dozen or so in Oda.
- **Each has a past.** Like a shop's made things (`Generators::Provenance`): a maker and its wearers. A dungeon's heart can be a mask, and the history can write masks into family feuds.
- **Anyone can wear one, one at a time.** A party with one mask decides each day who carries it.
- **A mask can speak.** As an NPC the GM speaks as: it tempts, comments, remembers who wore it before.
- **Transformation** (the tokusatsu henshin). Once per battle or per rest, at a cost (HP or powder), the wearer transforms for a few turns: their sprite changes (with `flash` or `spin`), their stats rise, and the mask's own moves appear, ending in its finisher. Afterwards they're spent: slowed or weakened.
- **An element each.** A Thunder mask on a Firemancer is a real choice.
- **A coward can't transform.**
- **Giants.** Things woken from the deep carry a `giant` trait that a transformed wearer has a large bonus against. A mask makes a giant winnable, never required.

**In the engine:**

1. A **transformation** status that carries stats, grants abilities and changes art.
2. Equipment that grants an ability (the command to transform). Check whether items can already.
3. **Uniqueness.** Campaigns read the world's books live, so "only one exists" needs deciding: one per campaign is simple; one per world isn't.
4. `giant` as an `against` trait.

## 6. Engine additions, cheapest first

Each one goes in with the archetype that needs it, with its property specs green (`spec/battle/properties_spec.rb`).

| # | Addition | For |
| --- | --- | --- |
| 1 | `wounded` and `giant` as `against` traits | Courtsword, Ranger; masks |
| 2 | `with`: a bonus for a status on the user, optionally spent | Monk, Courtsword |
| 3 | Ignore defence; pierce resistance; same-type bonus | Monk, mancers |
| 4 | Dispel: cleanse the good statuses | Magician |
| 5 | Regen and Reraise as statuses | Healer |
| 6 | Reload: a move leaves its user spent for some turns | Mancers, Ranger |
| 7 | **Stacking statuses:** a count as well as turns | Courtsword, Monk, mancers |
| 8 | Patience: power from the round's order | Courtsword |
| 9 | Reflect | Magician |
| 10 | Steal a buff | Thief |
| 11 | Transformation status | Masks |
| 12 | **Duel**, a battle kind | Everyone |
| 13 | Coward, a character state with its effects | Everyone |
| 14 | Locks and traps in dungeons | Thief |
| 15 | Iai stance: a reaction before the blow | Courtsword |
| 16 | A companion that stays the whole battle | Ranger |

## 7. Open questions

1. **The duel's core:** the stance mind game (§4.1) or the archetype's usual moves, one on one? Recommended: stances.
2. **Who duels?** People only (characters, the cast, antagonists), or monsters too? Recommended: people only. A beast can't be refused, so it can't make anyone a coward.
3. **Can a coward challenge,** or only wait to be challenged? Challenging gives the player a way out; waiting is harsher.
4. **Does refusing twice make it worse,** or is coward simply on or off?
5. **Powder** as the magic of Oda: keep, change or drop.
6. **Mancers:** one per type, written from one form, or a few by hand?
7. **Fire's rider:** poison worded as a burn, or a burn status of its own?
8. **The Monk:** forms that chain, or chi that banks?
9. **The Ranger:** a companion all battle, or random animals that come and go?
10. **Masks:** unique in the campaign or in the world?
