# Polychrome Online

A multiplayer tabletop RPG with a human GM and JRPG mechanics. The design
contract is [`docs/HANDOFF.md`](docs/HANDOFF.md). Read it before writing code.

## Status

- **Step 1 (done):** the battle resolver and stat derivation, pure Ruby in `lib/`.
- **Step 2 (done):** the books (Bestiary, Job Compendium, Grimoire, Armory) as
  Rails admin CRUD with rendered pages, plus base-world seed data.
- **Step 3 (done):** the battle screen. One party against one encounter, with
  Turbo Streams, a Stimulus event player and anime.js gestures.

```
bundle install
bin/rails db:setup      # creates the databases, loads the schema, seeds the base world
bin/rails server        # http://localhost:3000
bin/rspec               # all specs; bin/ci also runs RuboCop, Brakeman and audits
```

No database server needed: it's SQLite, with databases stored in `storage/`.

## Books

Every book is a resource namespace inside a world, e.g.
`/worlds/base/bestiary/monsters/ogre`. An entry has two faces: a form, and a
page with its stat block, prose, image and cross-references ("Used by",
"Taught by", "Dropped by", "Equippable by").

- The structured parts of an entry (stat blocks, effect lists, AI scripts,
  drop tables) are stored as JSON in exactly the shape the engine reads.
  Models validate them against the engine's own closed vocabularies:
  `Ability` asks `Battle::State.validate_ability!`, so the Grimoire can't hold
  an effect the resolver would reject.
- **Slugs are an entry's identity** inside its world and can't change after
  creation. They're the engine's ids and what AI scripts and drop tables use to
  refer to other entries.
- Each entry has an image slot (Active Storage) and a variant recipe (hue,
  scale, flip), applied with CSS. It also has `image_seed` and `image_prompt`
  columns for the future generation pipeline.
- `World#battle(seed:, party:, monsters: { "goblin" => 3 })` builds a battle
  state straight from the books. `Job#to_derivation`, `Job#passives` and
  `Item#to_equipment` feed `Stats::Derivation`.
- The learn table is `job_levels` (§4 calls it `job_learn_tables`): one row per
  job level, with its ABP cost and the ability it teaches.
- Items and equipment share one `items` table. `category` decides which: a
  consumable, or equipment for a slot.
- There's no authentication yet. The books are an open admin surface.

## Battle screen

Start one from a world page (**New battle**), then open the battle URL in other
browsers and have each player take a seat.

- `BattleRecord` is the persisted battle (the `battles` table). It isn't called
  `Battle` because that's the engine's namespace. `#apply!` runs the resolver
  inside one SQLite write transaction and stores the action in
  `battle_actions` and the resolver's events in `battle_events`. `#replay`
  rebuilds the state exactly from `initial_state` and the action log.
- **One broadcast per action (§6).** Each action broadcasts a *beat*: the
  events, the board before them and the board after them. The
  `battle-player` Stimulus controller plays beats in order as anime.js
  timelines, and swaps in the "after" board only when the timeline completes.
  Log text is written server-side (`BattlesHelper#battle_log_line`), so the
  JavaScript never describes or computes an outcome.
- **Skip and fast-forward.** Skip is `timeline.complete()`, which still
  applies every change in order. The GM's fast-forward sets the playback speed
  for everyone. A reload or late join renders the current state and never
  replays events.
- **Command panel.** Each seat has its own panel, a Turbo Frame that reloads
  after each beat. After an action, the response is a placeholder with no
  battle state in it, so the panel can't spoil a round before it has played.
- **Input timer.** It is a `BattleTimeoutJob` scheduled for the round's
  deadline. When it fires, missing commands default to each unit's last one,
  or Attack.
- **Seats need no accounts yet.** A seat (GM or a party member) is remembered
  in the session, and anyone can take any seat. The server does enforce that
  a player can only command their own unit and only the GM can override.
- **Art comes from the books.** A unit's sprite is its monster's or job's
  image slot, with the variant recipe applied; without an image it shows a
  lettered plate. Sprite rips go in through those image slots (stored
  locally in `storage/`), never into the repo (§8).
- **The party is a stand-in** until characters exist in step 4
  (`QuickParty`): a name and a job at a fixed base stat line, with the job's
  best gear from the Armory.

## Layout

| Path | What |
| --- | --- |
| `app/models`, `app/controllers/{bestiary,compendium,grimoire,armory}` | The books |
| `app/models/battle_record.rb`, `app/jobs/battle_timeout_job.rb` | Persisted battles, the action/event log, the input timer |
| `app/javascript/controllers/battle_player_controller.js`, `app/javascript/battle/gestures.js` | The event player and the motion gestures (§3.2) |
| `db/seeds/base_world.rb` | The base world's first entries (idempotent) |
| `lib/stats/derivation.rb` | `Stats::Derivation.derive` (base × job + equipment + passives) and `.effective` (+ buffs + statuses) |
| `lib/battle/resolver.rb` | `Battle::Resolver.apply(state, action) -> [new_state, events]` |
| `lib/battle/effects.rb` | The mechanic primitives (§3.1) and their formulas |
| `lib/battle/ai.rb` | Enemy condition/action scripts |
| `lib/battle/state.rb` | Closed vocabularies, and `Battle::State.build` for initial state |
| `lib/battle/replay.rb` | `Battle::Replay.run(initial_state, actions)` |
| `spec/battle/properties_spec.rb` | Invariants checked after every action in 250 chaotic seeded battles |
| `spec/battle/replay_spec.rb` | A full GM-run boss fight that replays exactly |

## Engine contract

**State** is a plain hash with string keys and only JSON types. It is what the
`battles.state` column will store. `Battle::State.build(seed:, party:, enemies:,
abilities:, escapable:)` makes one. Unit stats come in already derived by
`Stats::Derivation`. The ability library is copied into the state, so a battle
doesn't depend on later Bestiary edits (§9.8).

**Actions**

```ruby
{ type: "command", actor: "vivi", command: { kind: "ability", ability: "fire", target: "goblin_a" } }
{ type: "command", actor: "bartz", command: { kind: "defend" } }   # or kind: "flee"
{ type: "timeout" }                                                # input timer expired
{ type: "gm_override", op: "auto", unit: "locke", note: "..." }
# other GM ops: execute_round, set_hp, set_mp, add_status, remove_status, end_battle
```

An illegal action raises `Battle::InvalidAction` and leaves the state alone.
Rounds are Dragon Quest style: when the last party member able to act submits
a command, the whole round runs in speed order. A missing command (from a
timeout, `auto` or `execute_round`) defaults to the unit's last command if it's
still usable, otherwise to Attack.

**Events** include the handoff's list (`attack damage miss crit cast heal
status_applied status_expired ko turn_start turn_end flee victory defeat
gm_override`) plus: `command_accepted round_start turn_order round_end revive
defend buff_applied buff_expired turn_skipped action_failed timeout`.
Each event is a hash like `{"type" => "damage", "target" => "goblin_a",
"amount" => 24, "hp" => 21, ...}`. Every event that changes HP carries the
resulting `hp`, so the view never computes an outcome.

## Departures from the handoff

- **RNG.** The handoff says `Random.new(seed)`, but Ruby's `Random` can't
  expose its internal state as data. The resolver uses a 32-bit mulberry32
  whose whole state is one integer (`state["rng"]`). A battle can resume
  exactly from any persisted state, which is what the handoff is asking for.
- **Abilities take a list of effects** instead of one primitive, e.g. Bio is
  `elemental(dark)` + `status(poison)`. The list only draws on the closed
  primitive set, so the vocabulary stays closed.
- **Buff/debuff `amount` is a percentage**, so it scales across levels.
- **`haste`/`slow` are statuses** that modify agi through `Stats::Derivation`.
  `blind` halves physical hit chance. `sleep` and `paralyze` skip turns, and
  a physical hit ends sleep.

## Not in yet (deliberately)

Items and inventory (step 4), drop tables, and ABP awards. The victory event
sums the enemies' `rewards` hashes but awards nothing itself. All the numbers
are first guesses (§9.2) and will change in playtesting.
