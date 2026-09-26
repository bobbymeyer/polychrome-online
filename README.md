# Polychrome Online

A multiplayer tabletop RPG with a human GM and JRPG mechanics. The design
contract is [`docs/HANDOFF.md`](docs/HANDOFF.md). Read it before writing code.

## Status

Build order step 1 is done: the battle resolver and stat derivation, as pure
Ruby with RSpec. There's no web app yet. When the Rails app arrives, `lib/`
carries over unchanged.

```
bundle install
bin/rspec
```

## Layout

| Path | What |
| --- | --- |
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
