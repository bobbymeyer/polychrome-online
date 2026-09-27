# Polychrome Online

A multiplayer tabletop RPG with a human GM and JRPG mechanics. The design
contract is [`docs/HANDOFF.md`](docs/HANDOFF.md). Read it before writing code.

## Status

- **Step 1 (done):** the battle resolver and stat derivation, pure Ruby in `lib/`.
- **Step 2 (done):** the books (Bestiary, Job Compendium, Grimoire, Armory) as
  Rails admin CRUD with rendered pages, plus base-world seed data.
- **Step 3 (done):** the battle screen. One party against one encounter, with
  Turbo Streams, a Stimulus event player and anime.js gestures.
- **Step 4 (done):** characters and jobs: creation, EXP and levels, ABP and job
  levels, ability slots, equipment from a shared bag, and battle results that
  flow back to the party.
- **Step 5 (done):** the table: chat with portraits and expressions, and GM
  possession of NPCs.
- **Step 6 (done):** the pointcrawl map with GM edit tools, travel, and the
  Encounter Tables book.
- **Step 7 (done):** the town and dungeon generators, the Gazetteer and
  Generator Tables books, and exploring dungeons room by room.
- **Step 8 (done, without pins):** campaign flags, and a GM changes page listing
  every override on generated locations, each with a revert. World-version
  pins are deliberately not built yet: campaigns read the books live, so a
  change to a book shows up in every campaign straight away.
- **Step 9 (done):** the asset pipeline. Every image slot can be uploaded or
  generated with ComfyUI: all seven books, and each speaker's portraits. The
  prompt is composed in layers (world, content type, subject, and a portrait's
  expression), and each layer can add LoRAs. You pick from a strip of
  candidates, and the winner keeps its seed and recipe.
- **Accounts:** a login, with the first account as admin. A campaign has a GM
  account and characters belong to players. See "Accounts".
- **Presentation:** starts Swiss instead of SNES and diverges where play needs
  it, per [`docs/DESIGN.md`](docs/DESIGN.md). Inter
  in black on white, a 12-column grid, geometry for state, grey controls and red for
  game moves. The mechanics stay JRPG.
- **Play pass:** the menus play like a game. There's a keyboard cursor, a help
  line, targets highlighted on the field (and clickable), a "You" marker, and
  keys to skip playback and advance dialogue. See "Play" in `docs/DESIGN.md`.

```
bundle install
bin/rails db:setup      # creates the databases, loads the schema, seeds the base world
bin/rails server        # http://localhost:3000
bin/rspec               # all specs; bin/ci also runs RuboCop, Brakeman and audits
```

No database server needed: it's SQLite, with databases stored in `storage/`.

After a deploy, `bin/rails db:seed` adds any Base World entries that are new in
`db/seeds/base_world.rb` and leaves existing ones alone, so a GM's edits
survive. To put every Base World entry back to the seed data (after a
rebalance, say), run `bin/rails base_world:update`. It overwrites edits.

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

Start one from a campaign page (**New battle**), then open the battle URL in
other browsers and have each player take a seat.

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
- **Items.** A battle starts with the party's usable items from the campaign
  bag (`state["items"]`, counts shared by the whole party). "Item" is a
  command like an ability: it has no MP cost and silence doesn't stop it.
  Two players can't both queue the last one. An absent player never
  defaults to an item. When the battle ends, whatever was used comes out of
  the bag. Gear never comes into battle.
- **Items outside battle.** From a character's sheet, that character can use
  a healing or reviving item from the bag on anyone in the party.
  `Battle::Field` runs the same effect formulas, using the campaign's seeded
  RNG, so a Potion heals the same as in battle. Cures only work in battle,
  where statuses exist. Using items outside battle is blocked while a battle
  is on, because its settlement writes HP back.
- **The current battle.** The table's "… is on →" button follows the newest
  battle still being fought, for everyone, as battles start and end. Only
  that battle's log line says "Join the battle". The GM can **call off** a
  battle nobody will finish, from the campaign page or the battle. It then
  counts for nothing: no settlement, and HP and items stay as they were.
- **Everyone goes.** `BattleRecord.start!` broadcasts a `battle_start` stream
  action on the campaign's `:stage` stream, which every game page of the
  campaign subscribes to (`shared/_stage_stream`). `stage.js` waits for the
  dialogue to finish, plays the wipe and follows. The page you left is kept
  in `sessionStorage` for the "Back to …" link on the result panel.
- **Bosses.** A monster can be marked a boss in the Bestiary, with a line it
  says when it arrives. A battle is a boss fight when a marked boss is in it,
  or when it comes from a dungeon's boss room (`battles.boss`); its boss is
  the marked one, or else the strongest monster there. The battle page plays
  the entrance (`boss_intro_controller`), and the settlement line names what
  fell.
- **Input timer.** It is a `BattleTimeoutJob` scheduled for the round's
  deadline. When it fires, missing commands default to each unit's last one,
  or Attack.
- **Seats follow accounts** (see "Accounts"). The GM seat is the campaign
  GM's or an admin's, and a party member's seat is its player's. The server
  enforces that a player only commands their own unit and only the GM can
  override.
- **Art comes from the books.** A unit's sprite is its monster's or job's
  image slot, with the variant recipe applied; without an image it shows a
  lettered plate. Sprite rips go in through those image slots (stored
  locally in `storage/`), never into the repo (§8).
- **The party is the campaign's characters.** They bring their current HP/MP
  and derived stats in. When the battle ends, `BattleRecord#settle!` writes
  results back in the same transaction as the ending action (see below).

## Sound

- **Jingles** are synthesised in `app/javascript/sound.js` (WebAudio), so
  there are no sound files in the repo. `play(name)` plays one: the battle
  player plays victory and defeat, `stage.js` the encounter and boss calls,
  and a log line with a `cue` (`key`, `door`, `treasure`, set where
  `Location` writes the line) plays its jingle as it arrives live.
- **Music** comes from the world's uploaded tracks (`World::MUSIC`, one
  Active Storage attachment per scene, audio only, 25 MB each; removed
  tracks are purged in the background). Every game page names its track in
  `<meta name="polychrome-music">` (`ApplicationHelper#music_meta`), and one
  `Audio` element, which lives as long as the tab does, crossfades between
  tracks across Turbo visits.
- **The GM's choice** (`campaigns.music`: a scene or `silence`, nil to
  follow the scene) is set from the table and broadcast as a `music` stream
  action on the campaign's `:stage` stream. Battle pages ignore it.
- Muting is per device (`localStorage`).

## Characters and jobs

A world has campaigns (§4): a party, a shared bag, gil, flags, a map and its
locations. Worlds are live (§9.8): a campaign reads its world's books as they
are now (see "Campaign flags and GM changes").

- **Level:** comes from EXP (`Stats::Growth`, pure, like `Stats::Derivation`).
- **Stats are never stored.** The sheet shows each derivation stage: level
  base, × job, + gear, + the job's innates.
- **Job progress:** each job a character has held keeps its own ABP
  (`character_jobs`). A learn-table row's ABP is the cost of reaching that
  level from the one before, so a job is at level N once its total ABP covers
  the first N rows. New characters pick a starting level and job level.
- **Abilities:** a character can use what their current job has taught them,
  plus learned abilities from other jobs placed in that job's free slots
  (`jobs.ability_slots`; Freelancer 2, others 1, FF5-style).
- **Equipment** comes out of the party bag and goes back into it. Changing job
  returns gear the new job can't use to the bag.
- **Battle results:** HP/MP always carry over. On a victory, EXP is split among
  the characters still standing (FF5-style), each of them gets the full ABP for
  their current job, gil goes to the party, and dropped items go into the bag.
  The engine rolls drops at victory with the battle's own RNG, so loot is part
  of the replay. The result panel reports level-ups and newly learned abilities.
- **GM tools:** add items to the bag, adjust gil, grant EXP/ABP, and rest the
  party at an inn.
- **Why they're here:** a character has one line in their own words
  (`characters.motive`), on their card and sheet. It is also their battle cry.
- **Desperation moves** (FF6-style): a job can name any offensive Grimoire
  entry as its desperation move (`jobs.desperation`; each Base World job has
  one, found rather than learned). At a quarter HP or less, a character's
  Attack has a 30% chance to become that move instead, once a battle and for
  no MP. The resolver emits `desperation` before the move, from the battle's
  own RNG, so it replays exactly. The battle player stops for a cut-in in
  the character's colour, with their line and the move's name.

## The table (chat)

Each campaign has a **table** (`/campaigns/:id/table`), the live page for
everything outside battle.

- **Dialogue box vs chat (§9.5).** Following the handoff's lean, GM and NPC
  lines play in a dialogue box one at a time, typed out beside the
  speaker's portrait. Player lines go straight into the side log. A dialogue
  line joins the log only after the box has typed it. Click (or Escape) to
  finish a line or move to the next; queued lines also move on by themselves.
  Each viewer reads at their own pace.
- **GM possession.** From the GM seat, the composer's "Speak as" picks the
  narrator or any NPC, with an expression. The chosen speaker sticks between
  lines. The server decides who a line is from, based on the seat: players
  always speak as their own character.
- **Portraits and expressions.** NPCs and characters get one image per
  expression, from a closed set (neutral, happy, sad, angry, surprised,
  worried, determined). Missing ones fall back to neutral; for a character,
  then to their job's image; then to a lettered plate. Portrait reactions
  (e.g. angry → shake) use the same gestures as battle (§3.2), now in
  `app/javascript/motion/gestures.js`.
- **Whispers** go player → GM or GM → player. They're scoped broadcasts: each
  seat's page is signed only for the table stream plus its own whisper stream
  (the GM's, or that character's), so other players' browsers never receive
  them. After a whisper, the composer goes back to "Everyone".
- **Battles post at the table.** Each battle posts a line when it starts, with
  a "Join the battle" link, and a line with the outcome when it ends. Your
  table seat carries into the battle, so players land on their own character.
- NPCs belong to the campaign (the "Cast" section of the campaign page). The
  town generator in step 7 will create them too.
- **Taking a line back.** The GM can take back any line said at the table,
  and a player their own ("Take back" on the line, in the log). It goes from
  every viewer's log, and from their dialogue box if it's waiting or showing.
  What the game logged (system lines) stays.
- **Speaking in battle.** The battle page has the same composer, open for the
  GM, so a monster's taunt doesn't mean leaving the fight.
- **Choices.** `? Trust Cid | Refuse -> trusted_cid`, from the GM's composer
  or as the last line of a scene, puts a choice to the table. It comes up
  under the dialogue once the lines before it have been read. Each player
  picks for their character and can change their mind, and everyone sees who
  picked what. The GM settles it: "The party chose: …" is said, and the flag
  is set to the outcome and shown to players, for the next scene to follow.
  One choice is open at a time.
- **Checks.** The GM calls for one from the table: who tries, a stat (Str,
  Mag, Vit, Spr, Agi), a difficulty (Easy, Normal, Hard, Heroic) and what
  for. `Stats::Check` (pure) turns the character's stat into a chance: at
  Normal, a stat typical for their level is an even chance, each point
  counts for less at higher levels, and it's always 5–95%. The roll comes
  from the campaign's RNG. Everyone at the table watches the number spin
  and land; the log keeps the chance and the roll.
- **How a fight will go.** The battle form and a scene's battle ending show
  a forecast as the GM picks who fights and what they face:
  `Battle::Forecast` (pure) plays the fight out 20 times with everyone
  repeating their default command, and reports wins, HP left, how many go
  down and how long it takes, as Easy, Fair, Hard or Deadly. Real players
  do better than always attacking, so it is a floor.

## Scenes

The GM writes scenes before the session, on the campaign page, and plays
them from the table with one press (`Scene#play!`). A script reads like a
play, one line each: `Cid (worried): The airship won't hold.` speaks as
the NPC with that expression, and anything else is narration (a name that
isn't in the cast is an error, unless it's clearly a sentence). The lines
become table messages in order, so every viewer's dialogue box types them
out one after another. The scene can then end:

- **In a battle** against the monsters chosen for it. The battle starts
  straight away, and each viewer is taken to it once their dialogue box has
  finished the scene (`stage.js` waits for it).
- **With a place revealed** on the map.

A played scene stays in the list, greyed, and can be played again.

## Previously on…

Coming back to the table after a break (this device hasn't had it open for
three hours, or ever), a title card opens: the last session in brief
(`Recap`). A session is a run of log lines with no gap over three hours; the
recap is of the last one that has ended, so it still recaps last week once
tonight has started. It covers the road the party took (read from the travel
and dungeon lines), the battles and level-ups, keys and treasure found, the
flags the party knows that changed, and the last line said to the table.
Whispers are never in it. "Previously on …" under the table's title opens it
again at any time.

## The pointcrawl map

Each campaign has a map (`/campaigns/:id/map`), and the table shows it too.

- **Places and paths** are `map_nodes` (town, dungeon, field or event;
  revealed or hidden) and `map_edges` (open, dangerous or blocked, with an
  optional encounter table and travel event), per §4. They're drawn as SVG
  from Rails partials.
- **GM editing, all by clicking:**
  - Click empty ground to add a place, click a place or path to edit it in
    the side panel, and drag a place to move it.
  - From a place's panel: reveal it, connect it to another place, or put the
    party there.
  - From a path's panel: change its state, pick its encounter table, write
    its travel event, or cut it.
  - Every change reaches every viewer by Turbo Stream.
- **Scoped per audience:** the map is rendered twice, once for the GM (with
  hidden places, dimmed) and once for players (without them), each on its own
  signed stream. A hidden place never reaches a player's browser.
- **Travel:** the GM moves the party along a path from where it stands.
  Arriving reveals the destination. The table gets a departure line, then
  the path's travel event narrated in the dialogue box.
- **Encounters:** a path with an encounter table rolls on it: 25% of the time
  on an open path, every time on a dangerous one, never on a blocked one.
  - The roll (`Pointcrawl::Encounters`, pure) uses an RNG stored on the
    campaign, like a battle's, so the GM can't quietly re-roll.
  - A hit waits for the GM: **Fight** starts a battle for everyone standing,
    **Wave it off** clears it. Both are announced at the table.
- **Encounter Tables** is the sixth book (`/worlds/:world/encounters/tables`):
  weighted monster groups by terrain and tier (§2, §4), seeded with five
  tables. Monster pages list the tables they appear in.

## Towns and dungeons

A map place can hold a **location**, rolled from a Gazetteer template (§7).

- **Shops.** A town with a shop sells its stock for party gil and buys items
  back from the bag at half price (`ShopsController`, `Campaign#buy!` and
  `#sell!`). Gear someone is wearing can be sold too: it comes off, then
  sells. Only that character's player or the GM can do that. Players can
  only shop in the town where the party is; the GM can shop anywhere. Every
  purchase and sale is announced at the table.

- **Stored:** only template + seed + GM overrides. What the location contains
  is generated from those on every view, by the pure `Generators::Town` and
  `Generators::Dungeon`, then `Generators::Overrides`. Rendering is derived,
  never the source of truth (§12). Reroll = new seed.
- **Two new books.** The **Gazetteer** holds town and dungeon templates:
  service chances, roster and stock sizes, room counts, loops, decision
  weights, encounter table, boss. Each template's page renders an example
  you can reroll. **Generator Tables** hold the raw material: place and
  person names, NPC hooks, service names, building archetypes, shop stock,
  room names, room events, fork costs and treasure. A template chooses which
  tables it draws from.
- **Towns:** a service roster (inn, shop, guild, temple), townsfolk with
  one-line hooks (GM-only), shop stock with Armory prices, and an SVG skyline
  built from the building archetypes.
- **Dungeons:** a room graph that branches and loops, drawn as an SVG
  floorplan. Every room carries a decision (§7): an encounter from the
  template's encounter table, an event, treasure, or a fork with a visible
  cost on one of its ways onward. The deepest room holds the boss. The
  generator specs check this over hundreds of seeds.
- **GM controls (§7):**
  - **Reroll.**
  - **Pin:** pinned services and rooms survive a reroll. Pinning a
    townsperson makes them a real campaign NPC you can speak as at the table.
  - **Add:** write in an NPC, or add a room off an existing one.
  - **Place the boss.**
  - **Override the shop stock.**
- **Exploring a dungeon** (a nested pointcrawl):
  - The GM leads the party in and moves them room to room, and each room plays
    its decision at the table. Events are narrated in the dialogue box.
  - Encounters and the boss wait to be fought or waved off, as on the map.
  - The GM hands treasure over to the party bag. Taking a costly way posts its
    cost.
  - Players see only the rooms they've been in, plus the exits out of them.
- **Locks and keys.** A dungeon template asks for up to three locks. Each lock
  guards a way the party can't get around on the way to the boss: a path on
  the route, or every door into the boss's room. Its key is in a room they can
  reach first (behind the earlier locks, if there are several), so every locked
  dungeon can be solved; a spec checks this over hundreds of seeds. Locks and
  keys come in flavoured pairs from a "locks" generator table (Crystal portal
  and Blue crystal, Bone altar and Goat's skull). Walking into the key's room
  finds it, and crossing the lock with it opens the way for good.
- **Live updates** use Rails 8 page refreshes (morphing): each viewer re-fetches
  their own page, so what only the GM may see is never sent to a player.

## Campaign flags and GM changes

- **Flags (§4)** are the GM's campaign state: `met_the_king = yes`,
  `crystals_found = 2`. Whole-number flags get −1/+1 buttons. A flag marked
  public shows at the table under "The party knows"; the rest are GM-only and
  never rendered for players.
- **GM changes** (`/campaigns/:id/changes`) lists every override on the
  campaign's generated locations (§7: "GM diffs are overrides on top").
  That covers renames, pins, pinned or written-in NPCs, shop stock, placed
  bosses and added rooms. Each one reverts on its own; revert them all and
  the location is exactly what was rolled.
- **Worlds are live (§9.8, decided).** Campaigns read the books as they are
  now, so a GM can develop their world while playing it: retune the Knight and
  every Knight follows. A battle in progress is unaffected (it copies what it
  needs when it starts). Towns and dungeons are rebuilt from their seed and the
  current tables, so editing a table changes places already rolled, except
  what's pinned. To fork a world instead, start a new one from its books.

## Accounts

Everything needs an account, except signing in, making an account,
resetting a password, and `/up`. Sign-in is the Rails 8 authentication
generator (email and password, with `bcrypt`), plus a sign-up page.

| Who | What they can do |
| --- | --- |
| **Admin** (the first account ever made) | Everything: every world's books, art direction and book art. Can GM any campaign. Manages accounts on the Accounts page. |
| **A campaign's GM** (whoever started it, or whoever an admin hands it to) | Runs that campaign: the GM seat, map, flags, locations, battles, scenes, NPCs, the bag, rests, EXP grants, starting levels, and generating its speakers' portraits. |
| **A world's owner** (whoever made it, usually as a copy) | Changes its books as they play. So do the GMs of campaigns in that world. |
| **Anyone** | Starts a campaign in any world and GMs it. Makes a world, usually by copying one. Makes characters, which start at the party's lowest level, and sits as, equips and levels their own. Reads every book. |

- **The Base World is the admins'.** It has no owner, so only admins change
  it: a GM who wants to change the books as they play copies it ("Copy this
  world") and runs their campaign there. Worlds are live, so this is what
  keeps one GM's retuned goblin out of another GM's game.
- **Admin rules.** Anyone can be made an admin. The last admin can't be
  demoted or removed.
- **Seats pick themselves.** At a table or battle you haven't sat at, you're
  seated as your only character, or as the GM of your own campaign when you
  play nobody in it. Standing up ("Change seat") sticks. Seats belong to
  the account, so two people on one browser never share one.
- **The home page** lists your campaigns (ones you play in or GM), then the
  rest to join, then the worlds.
- **Claiming.** A character with no owner, such as one made before
  accounts existed, becomes yours when you sit as them. Campaigns made
  before accounts have no GM until an admin picks one; admins run them
  meanwhile.
- **Enforcement.** Pages hide what you can't do, and the server refuses it
  anyway. Seats are re-checked against the account on every request.
- **On a fresh deploy, make your account first.** Whoever signs up first
  becomes the admin.
- **Password reset emails** need Action Mailer configured for production
  (SMTP settings, and a `from` address in `ApplicationMailer`). Until then,
  an admin can't reset anyone's password from the app.

## Art (the asset pipeline)

Every image slot can be uploaded or generated with
[ComfyUI](https://github.com/comfyanonymous/ComfyUI) (§8):

- **Book entries** in all seven books. Upload on the edit form; generate in
  the Art section of the entry's page.
- **Speaker portraits,** one per expression, for NPCs and characters. Upload
  in their edit form; generate in "Generate portraits" below it.

- **The prompt is composed in three layers.** Each layer can add LoRAs:
  - **World:** the house style, the negative prompt, and optionally a
    checkpoint. Edited on the world's Art direction page.
  - **Content type:** framing per kind of entry, such as "profile view, full
    body", plus a negative prompt, size, and whether to remove the background.
    Also on the Art direction page, and seeded from `config/comfy.yml`.
  - **Subject:** a book entry's name and specifics (blank uses its
    description), or a speaker's name, title or job, and looks. An NPC's
    notes are GM-private and never go into a prompt.
  - **Expression** (portraits only): words per expression from
    `config/comfy.yml`, such as "smiling happily".

  When the same LoRA appears in two layers, the later layer's strength wins,
  and 0 turns it off.
- **The workflow is built, not templated.** `Comfy::Graph` builds the ComfyUI
  graph from the composed recipe each time:
  1. Checkpoint.
  2. One chained LoraLoader per LoRA.
  3. The prompts, the sampler and the decode.
  4. Background removal, when the type asks for it and `COMFY_REMBG_NODE`
     names an installed node.
  5. SaveImage.
- **Candidates.** Generate queues 1–8 candidates, each its own ComfyUI prompt
  with its own seed. `ArtBatchJob` submits them and checks back every few
  seconds without holding a worker. Each image appears on the page as it
  lands, for everyone viewing it. Only the art section reloads (a Turbo Frame
  and a `reload_frame` stream action), so a half-typed form elsewhere on the
  page is left alone. For a portrait, the first candidate reuses the Neutral
  portrait's seed, so the face stays closer across expressions.
  "Use this" makes one the entry's image and
  stores its `image_seed`, `image_prompt` and full `image_recipe`, so it can
  be regenerated exactly. Uploading an image by hand clears them.
- **Settings** are environment variables, read by `config/comfy.yml`:

  | Variable | Default |
  | --- | --- |
  | `COMFY_URL` | `http://127.0.0.1:8188` |
  | `COMFY_CHECKPOINT` | `sd_xl_base_1.0.safetensors` |
  | `COMFY_REMBG_NODE` | blank (keeps backgrounds) |
  | `COMFY_REMBG_INPUT` | `image` |

  LoRA and checkpoint fields suggest whatever ComfyUI reports as installed.
- **ComfyUI on the same machine as the container.**
  - Start ComfyUI with `--listen`: by default it only accepts connections from
    127.0.0.1, which excludes the container.
  - Run the container with
    `--add-host=host.docker.internal:host-gateway`.
  - Set `COMFY_URL=http://host.docker.internal:8188`.
  - `SOLID_QUEUE_IN_PUMA` (set in the Dockerfile) runs the job worker that
    drives generation.
  - Images are also kept in ComfyUI's `output/polychrome/` folder.

## Layout

| Path | What |
| --- | --- |
| `app/models`, `app/controllers/{bestiary,compendium,grimoire,armory}` | The books |
| `app/models/battle_record.rb`, `app/jobs/battle_timeout_job.rb` | Persisted battles, the action/event log, the input timer |
| `app/models/campaign.rb`, `app/models/character.rb` | Campaigns, the party bag, characters, jobs, equipment and ability slots |
| `lib/stats/growth.rb` | EXP to level to base stats, and ABP to job level |
| `app/models/message.rb`, `app/javascript/controllers/dialogue_controller.js` | Table messages, their scoped broadcasts, and the dialogue box |
| `app/models/map_node.rb`, `app/models/map_edge.rb`, `app/javascript/controllers/map_editor_controller.js` | The pointcrawl map and its editor |
| `lib/pointcrawl/encounters.rb` | Encounter rolls on travel (pure, seeded) |
| `lib/generators/` | Town and dungeon generators, and GM overrides on top (pure, seeded) |
| `app/models/location.rb`, `app/views/locations/` | Campaign locations: skyline, floorplan, GM controls, exploration |
| `app/javascript/controllers/battle_player_controller.js`, `app/javascript/battle/gestures.js` | The event player and the motion gestures (§3.2) |
| `app/models/comfy/`, `app/models/art_*.rb`, `app/models/concerns/artwork.rb`, `app/jobs/art_batch_job.rb` | The asset pipeline: the ComfyUI client, the graph builder, layered recipes, batches and candidates |
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
# other GM ops: execute_round, set_hp, set_mp, add_status, remove_status, end_battle,
# add_unit (side: "enemy" | "party", unit: {engine spec}, abilities: {...}) and dismiss (unit:)
```

An illegal action raises `Battle::InvalidAction` and leaves the state alone.
Rounds are Dragon Quest style: when the last party member able to act submits
a command, the whole round runs in speed order. A missing command (from a
timeout, `auto` or `execute_round`) defaults to the unit's last command if it's
still usable, otherwise to Attack.

**Events** include the handoff's list (`attack damage miss crit cast heal
status_applied status_expired ko turn_start turn_end flee victory defeat
gm_override`) plus: `command_accepted round_start turn_order round_end revive
defend buff_applied buff_expired turn_skipped action_failed timeout
desperation unit_joined unit_left`.

**Joining and leaving.** `add_unit` brings a unit in mid-fight: enemy
reinforcements (named with the next free letter), or a guest on the party's
side who acts on its own AI script, takes no input and shares no rewards
(`"guest" => true`; the party is defeated when every character is down,
whatever the guests do). `dismiss` takes an enemy or guest off the field
(`"gone" => true`): it is out of play for good, never targeted or revived,
and gives no EXP or drops. If it was the last enemy standing, the party wins.
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

All the numbers are first guesses (§9.2) and will change in playtesting.
