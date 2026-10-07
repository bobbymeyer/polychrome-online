# Polychrome Online

A multiplayer tabletop RPG in the browser: a human GM, a table of 3–5 players,
and JRPG mechanics (FF5 jobs, Dragon Quest rounds, no dice the GM can tilt).
A Rails 8 app on SQLite, Hotwire and importmap.

## What to read

- [`docs/HANDOFF.md`](docs/HANDOFF.md) is the design contract: what the game is,
  the three layers, the closed vocabularies, the data model and the conventions.
  Read it before writing code. Where a shortcut conflicts with it, it wins.
- [`docs/DESIGN.md`](docs/DESIGN.md) is how it looks and plays: the Swiss
  surface, the Stage, the table and the battle screen, and every divergence from
  the starting point.
- [`docs/STORY.md`](docs/STORY.md) is the plan for procedural story (built and to come).
- **How to play** (`/how-to-play`, in the app) is the players' and GMs' guide.
- **How a feature works** is in its code: each model, concern and pure module
  opens with what it is for, and its spec says what it does. `lib/battle` and
  `lib/stats` are the rules engine (pure Ruby, no Active Record);
  `Battle::Resolver` documents the actions it takes.

## Running it

```
bundle install
bin/rails db:setup      # creates the databases, loads the schema, seeds both settings
bin/rails server        # http://localhost:3000
bin/rspec               # every spec; spec/system drives the live pages in headless Chrome
bin/ci                  # the specs, RuboCop, the gem and importmap audits and Brakeman
```

No database server: everything is SQLite, in `storage/`, including Solid
Queue, Solid Cache and Solid Cable. Set `CHROME_BIN` to run the system specs
against a particular Chrome or Chromium.

## The seeded settings

`db:seed` seeds the **Base World** (`db/seeds/base_world/`) and **Greenware**
(`db/seeds/greenware/`), a second setting written against the same books
through the same seeder: the proof that another author can.

- `bin/rails db:seed` adds entries that are new in the seed files and leaves
  existing ones alone, so a GM's edits survive a deploy.
- `bin/rails base_world:update` puts every Base World entry back to its seed
  data (after a rebalance, say). It overwrites edits.
- `bin/rails worlds:seed[greenware]` seeds one setting alone, and
  `bin/rails worlds:update[greenware]` puts it back to its seed data.

All the numbers are first guesses (HANDOFF §9.2) and will move in playtesting.

## Accounts

Everything needs an account except signing in, signing up, resetting a
password, `/up`, and the join page an invite link opens. **The first account made is the admin**, so on a fresh
deploy make yours first. A player who joins from the shared screen's QR code
with just a name gets a guest account.

| Who | What they can do |
| --- | --- |
| **Admin** | Everything: every world's books, any campaign's GM seat, the Accounts and Settings pages. The last admin can't be demoted or removed. |
| **A campaign's GM** (whoever started it, or whoever an admin hands it to) | Runs that campaign: the GM seat at its table and battles, Prep, its map and places. |
| **A world's owner** (whoever made or copied it) | Changes its books as they play, as do the GMs of campaigns in it. The Base World has no owner: GMs copy it to change it. |
| **Anyone** | Starts and GMs a campaign in any world, makes a world, makes characters and plays their own. |

Pages hide what you can't do and the server refuses it anyway
(`Authorization`, `TableSeat`, `BattleSeat`).

## Deploying

- The `Dockerfile` sets `SOLID_QUEUE_IN_PUMA`, which runs the job worker inside
  Puma. It isn't optional: a battle's round timer is a job (`BattleTimeoutJob`),
  and so are the language model's drafts.
- Images and music are made outside the game, in baible, and uploaded into
  their slots (HANDOFF §8). They're Active Storage files in `storage/`. Sprite
  rips used as placeholders go in the same way and never into the repo.
- Password reset emails need Action Mailer configured for production (SMTP,
  and a `from` address in `ApplicationMailer`).

## The language model

Optional. With one set up, the GM can ask it for drafts while preparing and
world building (secrets, clocks, scenes, modes, book descriptions, a setting's
types, skills and jobs). Nothing it writes is used until it's kept through the
same forms as writing by hand. Without one, none of this shows.

It can be anything that answers the OpenAI-compatible chat API over HTTP:
llama.cpp's server, llama-swap, Ollama (`…:11434/v1`), LM Studio, vLLM or a
hosted API. An admin sets its address and model on the Settings page
(`/settings`). A blank field falls back to the environment, which
`config/llm.yml` reads. Tokens, headers and passwords stay in the environment,
never in the database, and error messages never repeat them.

| Variable | Default | What |
| --- | --- | --- |
| `LLM_URL` | blank (off) | The API, up to `/v1`. A path prefix and `https://user:pass@host` basic auth both work |
| `LLM_MODEL` | blank | The model to ask for, as the server names it |
| `LLM_TOKEN` | blank | Sent as `Authorization: Bearer …` |
| `LLM_HEADERS` | `{}` | Other headers a proxy wants, as JSON (Cloudflare Access's, say) |
| `LLM_TIMEOUT` | `120` | Seconds, room for the server to load the model |

**Can't reach it?** "Check the connection" on the Settings page, or
`bin/rails services:check` inside the app's container, walks through the
address, the name, the connection and the answer, and says what usually goes
wrong at the step that fails. The usual one: inside a container, 127.0.0.1 is
the container itself. Make the server listen beyond 127.0.0.1, run the
container with `--add-host=host.docker.internal:host-gateway`, and use
`http://host.docker.internal:<port>/v1`.

## Where things are

| Path | What |
| --- | --- |
| `lib/battle/` | The battle resolver (`Battle::Resolver.apply(state, action) -> [state, events]`), its effects, AI, types and replay. Pure |
| `lib/stats/` | Stat derivation, growth (EXP and ABP), mastery and checks. Pure |
| `lib/pointcrawl/`, `lib/generators/`, `lib/story/` | Travel, encounters and the overnight step; the town, dungeon and history generators; the story matcher. Pure, seeded |
| `app/models/battle_record.rb`, `app/models/battle_record/` | A battle in play: persisting, broadcasting and timing what the resolver decides, and settling it |
| `app/models/battle_state.rb`, `battle_unit.rb`, `battle_move.rb`, `battle_command.rb` | The resolver's state as the pages read it |
| `app/models/campaign.rb`, `app/models/campaign/` | A party's run through a world, one concern per story (the bag, travel, the table's controls, rumours…), and `Campaign::Night` |
| `app/models/`, `app/controllers/<book>/` | The books (Bestiary, Compendium, Grimoire, Armory, Encounter Tables, Gazetteer, Generator Tables) and the setting's canon |
| `app/javascript/controllers/battle_player_controller.js`, `app/javascript/battle/`, `app/javascript/motion/` | The battle's event player, and the motion gestures (HANDOFF §3.2) |
| `db/seeds/` | The Base World and Greenware, one file per book |
| `spec/battle/properties_spec.rb` | Invariants checked after every action across hundreds of chaotic seeded battles |
