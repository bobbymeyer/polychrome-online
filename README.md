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
- **Second play pass (the first hour):** invites that let friends make their own
  characters, only your own campaigns at home, a first-session checklist, a
  starting town with roads and potions, the story on screen instead of in the log,
  a fair battle clock, the GM's call after a wipe, and phone layouts. See "Play"
  in `docs/DESIGN.md`.
- **Third play pass (the game):** a boss's entrance written from the place's
  past and a fanfare for a cleared dungeon that stops the clocks it drove; a
  Base World with a thread (the Barrow Lord's silver), places found by what
  towns are saying, and roads to open later; four-step gear ladders, a point
  per level in every stat, lessons to job level 100 with a capstone, and
  "next" on the sheet and results; and players voting on where next. See
  "Play" in `docs/DESIGN.md`. After a deploy, `bin/rails db:seed` adds the new
  Base World entries; `bin/rails base_world:update` also rewrites the learn
  tables and stock (and overwrites edits).
- **Balance pass:** the Base World's monsters are tuned for a level-5 party
  (fights of 3 to 8 rounds that cost HP; bosses a party wins by healing and
  casting, and loses by only attacking), its types spread so no job hits
  everything double, and every boss has a move to answer. Signature moves
  cost MP where they beat Attack; buffs raise the weapon too; Channel doubles
  the next spell; Haste is a second go each round; spells grow with the
  caster; MP comes back slowly, and a night in the open brings back half of
  it. Each job learns something every few fights, to a capstone at job level
  50. Run `bin/rails base_world:update` after deploying to take the new
  numbers (it overwrites edits to the Base World).

```
bundle install
bin/rails db:setup      # creates the databases, loads the schema, seeds the base world
bin/rails server        # http://localhost:3000
bin/rspec               # all specs; bin/ci also runs RuboCop, Brakeman and audits
```

No database server needed: it's SQLite, with databases stored in `storage/`.

After a deploy, `bin/rails db:seed` adds any Base World entries that are new in
`db/seeds/base_world/` and leaves existing ones alone, so a GM's edits
survive. To put every Base World entry back to the seed data (after a
rebalance, say), run `bin/rails base_world:update`. It overwrites edits.

`db:seed` also seeds Greenware (`db/seeds/greenware/`), a second setting
written against the same books: its own types, skills, origins, words,
calendar, atlas, cast, fronts, codex and a written-in pocket history. Seed
one setting alone with `bin/rails worlds:seed[greenware]`, or put it back to
its seed data with `bin/rails worlds:update[greenware]`.

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
  scale, flip), applied with CSS. How it's drawn lives in its `Art`: the art
  notes, LoRAs and model it adds to a prompt, and the seed, prompt and recipe
  of its generated picture. Speakers, the cast, portraits and mode pictures
  have one too. Each still reads and writes these as `entry.art_notes`,
  `entry.image_seed` and so on (`Drawn`).
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
- **Signature commands and passives.** A job has a signature command
  (`jobs.signature`, any Grimoire ability), always on its menu while in the
  job, learned or not, and a passive (`jobs.passive`, one of
  `Battle::PASSIVES`). A character has the current job's passive plus every
  mastered job's, so mastery keeps it for good. The Base World's:
  - **Freelancer:** Rally
  - **Knight:** Cover, Second Wind
  - **Thief:** Mug, First Strike
  - **Monk:** Focus, Counter
  - **Black Mage:** Channel, Clear Mind
  - **White Mage:** Pray, Regen
  - **Red Mage:** Flame Blade, Regen
  - **Summoner:** Carbuncle, Clear Mind (plus the summons)
  - **Geomancer:** Gaia, Regen
  - **Dragoon:** Jump, First Strike

  Each new job has its own learn table and desperation move.
- **Terrain.** A battle has a terrain type: from the encounter table's
  terrain on the road or in a dungeon (forest is grass, crypt is ghost, sea
  is water), or picked on the battle form. Moves typed `terrain` take it.
- **The end of a fight** shows a card for each ability learned (with what it
  does) and for each job mastered (with the passive now kept).
- **Why they're here:** a character has one line in their own words
  (`characters.motive`), on their card and sheet, and under their name on
  their "You" card at the table. It is also their battle cry.
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
  for. `Stats::Check` (pure) rolls a d100 and adds each modifier in turn:
  the character's stat against what's typical for their level (each point
  counts for less at higher levels), then any bonus (an archetype good at
  the skill, an origin). The total has to reach what the difficulty needs
  (51 at Normal: a typical stat is an even chance); a natural 1–5 always
  fails and a natural 96–100 always succeeds, so it's always 5–95%. The
  roll comes from the campaign's RNG. Everyone at the table watches the
  number spin and land, then move with each modifier; the log keeps the
  roll, the steps and the total.
- **How a fight will go.** The battle form and a scene's battle ending show
  a forecast as the GM picks who fights and what they face:
  `Battle::Forecast` (pure) plays the fight out 20 times with everyone
  repeating their default command, and reports wins, HP left, how many go
  down and how long it takes, as Easy, Fair, Hard or Deadly. Real players
  do better than always attacking, so it is a floor.

## Scenes

The GM writes scenes before the session, on the campaign's Prep page, and plays
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
flags the party knows that changed, secrets found out and public clocks that
filled, and the last line said to the table.
Whispers are never in it. "Previously on …" under the table's title opens it
again at any time.

## Local co-op

For a table around a TV, or a call with one shared stream: one **shared
screen** everyone watches, and phones as **controllers**. People talk out
loud (or on voice chat), so the app doesn't need to carry the talking.

- **The GM starts it** from the table ("Play around one screen"): open the
  shared screen on whatever drives the TV or the stream. It shows a QR code,
  a link and a six-letter code.
- **Players scan and pick a character, or make one.** No account needed:
  someone not signed in gives a name and gets a guest account
  (`users.guest`), which plays like any other. The QR code is the campaign's
  invite link with `?view=controller`; the same link without it (the campaign
  page's "Invite players") brings a remote player to the table. The code can
  be replaced ("New link") to shut old links out.
- **Views, not new pages** (`LocalCoop`). The table and battle pages render
  as `?view=screen` or `?view=controller` (`?view=off` to leave). The view is
  kept per campaign in the browser session, so it survives being pulled into
  a battle and back.
  - **Screen:** map, dialogue, choices, checks, the party's HP and the join
    code, big. No menus. It renders as a spectator whoever is signed in,
    so the GM's hidden places, notes and whispers never reach the TV. In
    battle: the board and the dialogue, no command panel. It has the sound.
  - **Controller:** your character's HP and MP, your picks when the table has
    a choice, your commands in battle. The map, dialogue box and check
    moments stay on the screen. It's quiet. In battle the board still plays
    off screen, so your commands wait for each beat just as the screen does.
- **Auto.** A player can put their own character on auto from the command
  panel ("Go on auto"), to talk and let the fight run. Picking a command
  takes them off it. The timer stays.

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
- **Services.** Each of a town's services is a collapsible panel under
  Services, named for its building and keeper. A building in the skyline
  opens its panel too, and panels stay as you left them after paying.
  A character pays from the party's purse (`Campaign#use_service!`): a player
  for their own character, the GM for anyone, only in the town where the
  party is, and never mid-battle. Prices are gil per level of the character
  served, with a floor (`Campaign::SERVICE_PRICES`).
  - **Inn:** a night's rest, full HP and MP. It can't help the fallen.
    "Rooms for everyone" pays for all who need one at once.
  - **Temple:** a fallen character is raised, whole again.
  - **Guild:** a rumour. The table is told the GM owes that character
    something true.

  The GM's free "Rest" on the campaign page is still there, for when the
  story says so.

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
- **Townsfolk couplets:** each townsperson also has two lines in their own
  words, a memory and a wish, from a world's memories and wishes tables ("I
  lost my brother on the road to Greyford." / "I keep a lantern in the window
  for him."), shown to everyone. Any two go together. A wish can be for
  something the party can bring (`Location::Wishes`): an item, which is a thing
  to do in that town while the bag holds it ("Bring Oskar a Remedy", voted on
  like any other), or the nearest dungeon cleared (`{dungeon}`), and then
  they're the one who welcomes the party back for it. Either is a deed, so the
  town thinks better of the party. Couplets are drawn after everything else,
  so towns rolled before them keep their people, stock and skyline; a place
  the party has been keeps the tables it was found with until it's rerolled.
- **Dungeons:** a room graph that branches and loops, drawn as an SVG
  floorplan. Every room carries a decision (§7): an encounter from the
  template's encounter table, an event, treasure, or a fork with a visible
  cost on one of its ways onward. The deepest room holds the boss. The
  generator specs check this over hundreds of seeds.
- **Forks cost something, and buy something.** A fork-costs row says in
  brackets what the costly way takes, the way a thing to do's are written
  (`Toll`): `pay 100`, a number of parts of the day, or outcomes from the one
  closed set (`Outcome`), which now has what takes as well as what gives:
  `hurt 10` (a share of everyone's HP, never the last), `weary 25` (of their
  MP) and `ambush` (a fight from the place's encounter table, waiting for the
  GM). It's taken the first time the party goes that way, refused if they
  can't pay, and "Where next?" names it ("(costs 10% of HP)"). A row without
  brackets is a cost the GM plays out. The generator makes the costly way the
  shortcut to the boss (when there's another way round) or the only way to
  treasure on that side, and the fork says so. That draws nothing, so the rest
  of a dungeon rolls as it did.
- **A hundred rolls:** each template's page links to a report of what it
  makes over a hundred seeds (`Generators::Report`): sizes (least, average,
  most), how often each service or decision comes up, what forks buy and
  whether the game or the GM takes their cost, what a dungeon was and how it
  fell (from the world's lore, as for a place the history never saw), locks
  left out for want of somewhere to hide their key, how often the generator
  had to make something up ("Stranger 1"), and for every table it draws on,
  how many rows came up, the most common, and the rows that never did. It's
  how a world builder finds thin tables before players do, and how a change to
  a generator gets judged.
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
  - Encounters and the boss wait to be fought or waved off, as on the map. A
    room is dealt with when its fight is won (an ordinary one, when waved off
    too): lost or fled, the boss waits there still, and the place isn't
    cleared.
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

## The setting: canon, voice, words, time and origins

A world is a setting, not only rulebooks. Its editors write these once, and
every campaign in it uses them.

- **Atlas** (`/worlds/:slug/atlas`): named places and the roads between them.
  - **Place kinds:** a town or dungeon can be rolled from a Gazetteer
    template with a fixed seed, so Varn is the same Varn in every campaign.
    Landmarks (a lighthouse, a manor) and wilds (a marsh, a sea) are places
    with no generator.
  - **What a place carries:** a description players read on the map, GM
    notes, and whether players know it from the start.
  - **Roads** have a state, what waits on them, what the table hears on the
    way, and how long they take.
- **Cast** (`/cast`): the setting's people, with portraits, what people say
  about them, GM notes, a home, and optionally a Bestiary entry that makes
  them an antagonist. An antagonist whose home is a dungeon waits in its boss
  room, with their own entrance, and slips away the first time they're
  knocked out: they come back stronger, and their clocks keep running.
- **Codex** (`/codex`): lore pages by category (faction, faith, history…).
  Each page is public or GM only, and its GM notes are never shown to
  players. Players can read the public pages from the campaign page.
- **A new campaign starts with the atlas on its map and the cast as its
  NPCs,** unless the GM chooses to start from nothing. Places and people
  the world gains later can be brought in from the campaign page, never
  twice. What's brought in is the campaign's to change.
- **Fronts** (`/fronts`): the setting's pressures, written once.
  - A front has clocks and the secrets behind them, naming atlas places and
    cast.
  - A GM deals one into a campaign, where it becomes that campaign's own
    clocks and secrets, linked to what it brought in.
  - A front's clock can say what a place becomes when it fills, and dealing
    it in prepares that mode.
- **History** (`/history`): a small history of the setting, rolled over its
  atlas before play.
  - **What it rolls:** a few families over the atlas's places, for a
    century or so (40 to 300 years). They found towns, build manors, mines
    and abbeys, marry, quarrel, feud, betray each other, drown, sell up and
    flee. Places burn, flood and get sealed. It stays local and pulp.
  - **What the table hears and what happened:** some events have a truth
    only the GM sees. "The Ashers lost their standing; nobody could say how"
    comes with who did it.
  - **Rerolling:** the history comes from a seed, so a reroll gives a new
    one. Families the GM keeps stay through rerolls, with their name, trade
    and seat. The world's `families` generator tables supply surnames, and
    its `names` tables given names.
  - **Writing it in:** it goes into the canon the GM already edits:
    - a History page and a page per family in the codex, with the truths in
      the GM notes;
    - the living head of each family in the cast;
    - a past on every place in the atlas;
    - each feud still running as a front, with its clock and its secrets.
  - **Writing it in again** replaces what it wrote before, except what the
    GM has changed since. **Taking it out** removes it, with the same
    exception.
- **Where things came from (provenance):** every town and dungeon has a
  past.
  - **Where it comes from:** the atlas place's past when the history wrote
    one or the GM gave it one. Otherwise the place rolls a small past of its
    own from its seed, not stored.
  - **Towns** have a founder, their old rivals and the feud still running.
  - **Dungeons** were something before: the Vell manor, the Pike mine,
    usually what their name says. So:
    - about half their rooms are that thing's rooms (a manor has a Nursery
      and a Wine Cellar);
    - the boss room is its heart, and whoever died there waits in it;
    - one event room shows how it fell;
    - the treasure comes with what the family lost there, and who made it
      for whom.
  - **What doesn't change:** the rooms' places and decisions.
  - **Shops:** a shop's made things (not its potions) can say who made them
    and who had them before.
  - **Editing a past:** it can be edited on the atlas place. Once edited,
    it's the GM's, and the history leaves it alone.
- **Voice** (on the world's edit page): tone and touchstones, and words or
  tropes to avoid. The language model writes in it.
- **Lines and veils:** lines never happen in the setting; veils happen
  off-screen. They are shown on the world and campaign pages, and the model
  never writes them, image prompts included.
  - **A table's own** (`Campaign::Limits`): anyone who plays in a campaign
    can add a line or a veil from the campaign page or the table's "What we
    know" drawer. No name is recorded; the table hears "New for this table,
    never: spiders." They are shown beside the world's (on the join page
    too), and the model is told both when it drafts for that campaign. Only
    the GM takes one off, on the campaign's edit page.
- **Words** (on the world's edit page): the setting's names for the game's
  fixed things.
  - **What can be renamed:** money, HP and MP, the five stats, the four town
    services and every status. The rules don't change.
  - **Services can be left out:** a secular setting has no temple in its
    towns.
  - **Blank keeps the game's word.** The words reach the table, towns,
    shops, messages, the battle board and its animations.
- **Time:** each campaign keeps a day and a part of it (dawn, day, dusk,
  night).
  - **What moves it:** journeys take their road's time, a rest sleeps until
    dawn, and the GM can pass time from the table.
  - **Clocks** can tick on each new day, so "the festival is in three days"
    is a three-segment clock.
  - **A world's calendar** names its weekdays and months.
  - **Deeds and reputation** (the campaign's Prep page, "Deeds"): what the party did
    that people will talk about.
    - **Recorded by themselves:** beating an antagonist for good, and
      clearing a dungeon by winning its boss fight. The GM records the rest,
      each with a sway from −2 to +2.
    - **The story travels:** each deed starts a rumour where it happened, so
      the party hears about themselves on reaching the next town.
    - **A cleared place changes things:** its dangerous roads go quiet, the
      secrets it kept come out, and the nearest town welcomes the party back
      with a hook and rooms on the house while they stay.
    - **Reputation:** every town the story reaches moves by the deed's sway,
      from Unwelcome to Heroes. Friends sell 5% cheaper per point, wary
      towns dearer, and at −3 nobody will trade or give the party a bed.
      Striking a deed takes it back. The language model sees it too.
  - **Prep** (`/campaigns/:id/prep`, the GM's): scenes, clocks and fronts,
    secrets, deeds, rumours and flags on one page of their own; the campaign
    page links to it.
  - **Legends** (`/campaigns/:id/legends`): the party's story by day (their
    deeds and the rumours they heard), what they found out, and the world's
    written history as far as it touches places they know. The GM's page
    has all of it, with what really happened.
  - **The world moves overnight** (`Pointcrawl::Overnight`, run from the
    campaign's own dice, so a night always goes the same way). Each new day:
    - **Clocks** that tick "now and then" go on a segment on a roll (about
      one night in three). The history's feud fronts tick this way.
    - **Rumours** travel one road from wherever they've got to, and fade
      after six days. They start when a place changes mode, when an
      antagonist is seen, when a caravan is lost, or when the GM lets one
      loose from the Prep page.
    - **Antagonists who got away** wander to a town or dungeon nearby,
      across wild country if need be, about half the nights.
    - **Caravans** are lost on dangerous roads between two towns, and prices
      go up 15% at both ends, easing back 5% a day. Shops charge and pay by
      today's prices.
    - **Secrets leak:** some nights a kept secret about a place gets out
      there as a rumour ("someone whispers…"). It isn't revealed; the GM's
      secrets list shows it's going round, and whether the party heard it.
    - **The GM gets a note** in the log, for their eyes only, of what moved.
      The party learns only what reaches them: arriving in a town, they
      hear what people there are saying, and a guild sells a rumour they
      haven't heard.
- **Origins** (`/origins`): where characters come from, each optionally
  better at one skill (+10 to its checks).
  - A character picks an origin, a home on the campaign's map, and ties to
    people in the cast ("owes her money").
  - These show on the sheet, and the language model sees the party this
    way.
  - Play notices them (`Campaign::Belonging`, on the "arrive" event in
    `Campaign::Happenings`). Arriving somewhere is a homecoming for anyone
    from there ("Vivi is home."). A tie is whispered to its player (and so to
    the GM) when the party arrives where the tied NPC lives, or when that NPC
    first speaks; once a session.
- **Copying a world** copies all of this with its books.

## Pressure and prep: modes, clocks, secrets

- **Location modes** are another state for a place, prepared ahead and set
  off at the table: the city burns, the mine floods, the festival starts.
  - **While it lasts:** services can be shut, the music changes, and
    arriving can mean trouble. The rest of the world stays as it is.
  - **A picture of its own.** A mode can have "art words" ("on fire, thick
    smoke") and a generated picture: the place's Gazetteer image, with those
    words added as one more layer. It starts from the same seed, so the
    place stays recognisable. While the mode lasts, the location page shows
    that picture instead.
  - Made on the location page ("GM: modes", "Pictures for modes").
- **Clocks** are things that happen if the party doesn't stop them: "The
  Brass Syndicate takes the docks", in 2–12 segments.
  - **Ticking:** the GM ticks them by hand, or they tick on their own on a
    rest, a journey or a failed check (a GM-called check or a field
    ability).
  - **Filling:** the table hears the clock's line, and it can set off one of
    a location's modes. The city burns because the party took too long.
    Winding a full clock back doesn't put the fire out; clear the mode on
    the location.
  - **Visibility:** public clocks show at the table under "The party knows"
    as a row of squares, filled black, red when full. Hidden clocks are the
    GM's alone and are never sent to players; nothing is said when they
    tick, and only their line when they fill.
- **Secrets** are things that are true ("the mayor pays the goblins"),
  written in prep and not tied to a scene, so the party finds them out
  however it gets there.
  - **About:** each can be about a place or someone.
  - **Revealing:** the GM reveals one at the table. It is announced, listed
    under "The party knows", and in the next recap. "Put back" undoes a
    slip.
  - **Field abilities:** a field ability with the `uncover` outcome brings
    one out on a success, preferring one about where the party stands.
- **Where:** clocks and secrets are on the campaign's Prep page, and in
  the GM's panels at the table for play. Both update live.

## Suggestions from a language model

With a language model set up (`LLM_URL`, see "Art"), the GM can ask it for
drafts while preparing and world building. It drafts and the GM decides:
nothing it writes is used until it is kept, and keeping goes through the same
forms and checks as writing by hand. Without one, none of this shows.

- **Prep** (the campaign's Prep page and location pages, for the GM):
  - **Secrets:** they tie together the cast and places already there.
  - **Clocks:** each has segments, triggers and the line the table hears
    when it fills.
  - **A scene:** its script goes onto the new scene form, with lines to fix
    flagged, for the GM to pick an ending and save.
  - **Modes for a place:** each has its line, what players read, services
    shut, music and art words.
- **World building** (for whoever can edit the world):
  - **An entry's description,** in the voice of the rest of its book (the
    entry's page). Only words: the numbers stay the author's.
  - **An ability family's four tier names and descriptions:** they go onto
    the family form.
  - **A setting's types, skills and jobs,** from a pitch (the world's page).
    Types and skills can be kept straight in; jobs need numbers, so they are
    ideas for the Compendium.
- **How:** each ask runs in the background (`DraftJob`), and the
  suggestions land on the page as they come. A new ask replaces the last
  one.
- **What the model is told:** a few compact lines about the setting and the
  campaign, the GM's notes included, so they go to the configured server.
  It is asked for JSON, and chatter or code fences around the JSON are
  ignored.

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
  worlds. Players come into someone else's campaign by its invite link; an
  admin also sees everyone else's campaigns.
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

- **Every image is composed in three layers:** world, content type,
  subject. Any layer can set a prompt, a model and LoRAs.
  - **World:** the house style ("line art, hand drawn, monochrome"), the
    negative prompt, a model and LoRAs. Edited on the world's Art direction
    page.
  - **Content type:** framing per kind of entry ("3/4 view of an object",
    "front view of a building"), plus a negative prompt, size, whether to
    remove the background, a model and LoRAs. Also on the Art direction
    page, and seeded from `config/comfy.yml`.
  - **Subject:** a book entry's name and specifics (blank uses its
    description), or a speaker's name, title or job, and looks. Also a model
    and LoRAs. Edited where it is generated. An NPC's notes are GM-private
    and never go into a prompt.
  - **Expression** (portraits only): words per expression from
    `config/comfy.yml`, such as "smiling happily".
- **How the layers combine:**
  - **Model:** the lowest layer that names one wins, then `COMFY_MODEL`.
    Anima is the default.
  - **LoRAs** stack in layer order, world first. A lower layer that names
    the same LoRA changes its strength in place, or switches it off with the
    "On" box. Each layer's page shows the stack from the layers above.
  - **Prompts** join in order: the model family's quality words, world
    style, type framing, subject, expression.
- **Model families** (`families` in `config/comfy.yml`) say how each kind of
  model runs. They cover Anima, Krea 2 (raw and Turbo), SDXL (with Pony,
  Illustrious/NoobAI and Lightning/Turbo variants) and SD 1.5. Each family
  sets:
  - loaders and the text encoder and VAE files to look for;
  - steps, CFG, and sampler and scheduler preferences;
  - CLIP skip and quality words;
  - whether it uses a negative prompt;
  - its trained size range. Sizes are scaled into it, keeping their shape.

  A model's file name picks its family. A name no family matches goes by
  where the file is: a checkpoint is taken for SDXL, a bare diffusion model
  for the default family. To teach it a new name, add a `match`. To support
  a new architecture that loads the same way, add a family.
- **The workflow is built for each image, not templated.**
  `Comfy::Workflow` asks ComfyUI what it has installed (`/object_info`, one
  node at a time) and builds the smallest graph that does the job:
  - **The model loads the way it is stored.** A checkpoint uses one
    `CheckpointLoaderSimple`. A bare diffusion model uses `UNETLoader`, plus
    the family's text encoder (`CLIPLoader` with the first `type` this
    ComfyUI offers) and its VAE.
  - **LoRAs chain in stack order.** Each uses `LoraLoaderModelOnly`, or
    `LoraLoader` for families whose LoRAs train the text encoder too.
    Switched-off LoRAs are left out.
  - **The negative prompt is never encoded when CFG is 1**, since the
    sampler ignores it (`ConditioningZeroOut` instead). With a large text
    encoder on CPU, that encoding can cost more than the image.
  - **Only what the family and server call for:** CLIP skip only when the
    family wants it, the first sampler and scheduler the server has,
    and no background removal (that comes after, outside ComfyUI).
  - **A missing file stops the batch before anything is queued**, whether a
    model, text encoder, VAE or LoRA, with a message naming what is
    missing. The entry's page previews the workflow ("UNETLoader →
    CLIPLoader → …") or what is missing, before you press Generate.
- **Candidates.** Generate queues 1–8 candidates, each its own ComfyUI prompt
  with its own seed and the same prompt text. ComfyUI keeps the loaded model
  and encoded prompt between them. `ArtBatchJob` submits them and checks back
  every few seconds without holding a worker. Each image appears on the page
  as it lands, for everyone viewing it. Only the art section reloads (a Turbo
  Frame and a `reload_frame` stream action), so a half-typed form elsewhere on
  the page is left alone. For a portrait, the first candidate reuses the
  Neutral portrait's seed, so the face stays closer across expressions.
  "Use this" makes one the entry's image and stores its seed, prompt and
  full recipe on the entry's `Art`, including the workflow's outline,
  so it can be regenerated exactly. Uploading an image by hand clears them.
- **Drafts first** (on by default for each batch): rough previews of about
  512 × 512 (the same pixel count, keeping the shape) in 16 steps, with
  background removal left for later.
  - **"Make this one properly"** re-renders a chosen draft at full size and
    steps, starting from the draft image itself. It scales the draft up and
    re-noises it in part (`draft.denoise` in `config/comfy.yml`), so it
    stays the same picture. A new image from the same seed at a different
    size would not.
  - **"Use the draft"** keeps a draft as it is.
  - **Timings:** each image shows how long ComfyUI spent on it, from
    ComfyUI's own history.
  - **Tuning** is on the Settings page: draft size and steps, how much
    "properly" changes a draft, and candidates per batch. Blank uses
    `draft` in `config/comfy.yml`; a family can also set its own
    `draft_steps`.
- **Background removal** is an optional step for any batch, on by default
  for content types marked to remove it. It happens outside ComfyUI, with a
  background-removal service of its own (`Cutout`, `config/cutout.yml`),
  called on each image once ComfyUI has rendered it.
  - **Which service:** rembg's HTTP server works as it is
    (`pip install "rembg[gpu,cli]"`, then `rembg s --host 0.0.0.0 --port 7000`),
    with its choice of models: `birefnet-general` (the default),
    `isnet-anime` for flat illustrated art, `bria-rmbg` and others. Anything
    that takes the image as a multipart `file` (and `model`) and answers
    with a PNG works too. Set the address and model on the Settings page,
    or with `CUTOUT_URL` and `CUTOUT_MODEL`.
  - **White inside the subject is kept:** a removal model takes whatever
    looks like the background, which on flat art drawn on white includes
    the white inside a creature. Only what's clear and connected to the edge
    of the picture is background; a clear patch closed in by the subject is
    put back from the picture as rendered (with libvips). A gap that really
    is background but is closed in, like an arm on a hip, is filled too.
  - **Checking:** every image that should have lost its background is
    checked for real transparency, and the strip says "background kept"
    when it didn't, or when the remover turned it down (the picture is kept
    either way).
  - **Not reachable:** the batch waits and tries again, as it does for
    ComfyUI. **Not set up:** backgrounds stay, and the pages say so.
- **Can't see ComfyUI?** Use "Connection" on the Art direction page, or
  `bin/rails services:check` inside the app's container. It checks, in turn:
  - the address: in a container, 127.0.0.1 is the container itself;
  - the name: `host.docker.internal` needs `extra_hosts`, and MagicDNS
    names don't resolve in containers;
  - the connection: a refusal usually means ComfyUI only listens on
    127.0.0.1, and a timeout on a 100.x address means the container isn't
    on the tailnet;
  - the answer: TLS trouble, or what's installed.

  It does the same for the language model, and never prints a token or
  password.
- **Optional: a language model writes the subject** (`PromptWriter`,
  `config/llm.yml`).
  - When `LLM_URL` is set, each batch first has the subject layer rewritten
    in the way the image model reads best: booru tags for Anima, Pony and
    Illustrious, plain sentences for Krea 2 and SDXL.
  - Style, framing and quality words are left as written.
  - It runs once per batch, in the job, and answers are cached.
  - There's a checkbox to skip it. If the model can't be reached, the batch
    goes ahead with the prompt as written.
  - It speaks the OpenAI-compatible chat API: llama.cpp's server,
    llama-swap, Ollama (`…:11434/v1`), LM Studio, vLLM or a hosted API.
- **ComfyUI and the language model can be anywhere the app can reach over
  HTTP.** They can run on the same machine, on a LAN or tailnet, or behind a
  proxy. Nothing assumes a particular machine or file layout.
- **Settings:** an admin sets them on the Settings page (`/settings`):
  - ComfyUI's address, its default model, and a background-removal node
    to try first;
  - the language model's address and model;
  - a check that the app can reach both.

  A blank field falls back to the environment variables below, which
  `config/comfy.yml` and `config/llm.yml` read. Only addresses and names go
  in the app. A token, a header or a password in a URL stays in the
  environment, never in the database or git, and error messages never
  repeat them.

  | Variable | Default | What |
  | --- | --- | --- |
  | `COMFY_URL` | `http://127.0.0.1:8188` | Where ComfyUI answers. A path prefix and `https://user:pass@host` basic auth both work |
  | `COMFY_TOKEN` | blank | Sent as `Authorization: Bearer …` |
  | `COMFY_HEADERS` | `{}` | Other headers a proxy wants, as JSON, such as Cloudflare Access's |
  | `COMFY_MODEL` | `anima-preview.safetensors` | The model when no layer names one |
  | `CUTOUT_URL` | blank (off) | A background-removal service (rembg's `rembg s`, or alike) |
  | `CUTOUT_MODEL` | `birefnet-general` | The model it should use |
  | `CUTOUT_PATH` | `/api/remove` | Where on it the image goes |
  | `CUTOUT_TOKEN` | blank | Sent as a bearer token |
  | `LLM_URL` | blank (off) | An OpenAI-compatible API, up to `/v1` |
  | `LLM_MODEL` | blank | The model to ask for, as the server names it |
  | `LLM_TOKEN`, `LLM_HEADERS` | blank | As for ComfyUI |
  | `LLM_TIMEOUT` | `120` | Seconds, room for the server to load the model |

  Models and LoRAs are picked from what ComfyUI reports as installed.
  - **Models** are grouped by the family each would run as (Anima, Krea 2
    Turbo, Pony, SDXL, and so on).
  - **LoRAs** are grouped by the subfolder they sit in, so keeping them in
    folders per family (`loras/SDXL/…`) keeps the list tidy.
  - **A saved name ComfyUI no longer has** stays selected under "Not on
    ComfyUI", so saving doesn't lose it.
  - **While ComfyUI isn't answering,** both are plain text fields.
  - **New files** appear within a minute.
- **Anima** needs three files, from Comfy Org's repackaged release:
  - `anima-preview.safetensors` in `models/diffusion_models`;
  - `qwen_3_06b_base.safetensors` in `models/text_encoders`;
  - `qwen_image_vae.safetensors` in `models/vae`.

  Its LoRAs patch the model only. On Apple Silicon, use bf16 files rather
  than fp8.
- **ComfyUI or a language model on the same machine as the container:**
  - Either service must listen beyond 127.0.0.1 for the container to reach
    it. For ComfyUI, start it with `--listen`; otherwise use its address on
    the LAN or tailnet.
  - Run the container with
    `--add-host=host.docker.internal:host-gateway`.
  - Use `http://host.docker.internal:<port>`.
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
| `app/models/comfy/`, `app/models/art_*.rb`, `app/models/concerns/artwork.rb`, `app/jobs/art_batch_job.rb` | The asset pipeline: the ComfyUI client, model families, the workflow builder, layered recipes, batches and candidates |
| `app/models/llm/`, `app/models/prompt_writer.rb` | The optional language model that writes image subjects |
| `db/seeds/base_world.rb`, `db/seeds/base_world/` | The base world's first entries, one file per book (idempotent) |
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

**Dice.** Every chance the engine rolls is a d100 (`Rng#d100`, the same
single draw as before, so the stream and the replays are unchanged), and
high is good, everywhere: a roll comes in when it reaches what was needed
(`Rng.target`: the top `chance` percent of the die, so a 70% chance needs
31 or over). The rolls that decide something are recorded in their events
as `roll` and `needed`: hits that miss, crits, statuses landing or
resisted, steals and getaways; a ruling's `custom_roll` also carries its
`modifiers` and `total`. The board shows each one as a die beside the unit (green when it
came in, wine when it didn't), and the log says "(rolled 98, needed 90 or
under)". The property specs check the dice are honest.

**Trying something.** A `custom` command carries the player's idea in
words ("kick the brazier onto them") and an optional target. The round
waits for the GM to rule on it (`rule`: a stat, a difficulty, where it's
aimed, what success does as effects from the closed primitive set, and a
line for success and one for failure). From the GM's panel that's quick
choices: just the story, damage (light to heavy, with a type), a status or
healing. On the character's turn a d100 is rolled against the same odds as
a check at the table (characters bring their level into battle for it).
Then the line is said and the effects land. A timer or "run the round
now" doesn't wait: an idea nobody ruled on is an Attack. An idea is never
repeated as a default.

**The timing meter.** An ability command can carry `"timing" => "perfect"`,
from the meter a player stops when confirming a move (Mario RPG's timed
hits). A Perfect raises every power in the move by a quarter and every
status chance by 20 points, and the move's `attack`/`cast` event says
`perfect`. It's part of the command, so replays stay exact. A repeated
command (auto, a timeout) never carries one. Missing costs nothing. The
meter can be switched off per device, and is off by default for reduced
motion.

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

## Damage types

`Battle::Types` (pure) holds 16 types (normal, fire, water, electric, grass,
ice, fighting, poison, ground, flying, psychic, bug, rock, ghost, dark,
steel) and Pokémon's chart between them. Fairy and dragon are left out.
The chart is on `/types`, linked from the Bestiary and the Grimoire.

- **Moves.** `elemental` takes a `type` (it used to take an element), and
  `physical` can take one. The basic Attack has none, so it always lands as it
  is: a party can always hit a ghost. Set a move's type in the effect rows.
- **Monsters** have a base type (`monsters.base_type`, normal by default).
  The engine takes one or two types per unit (`"types"`), and two multiply,
  as in the games. Characters are typeless.
- **Effectiveness.** A move does ×2 (super effective), ×½ (not very
  effective) or nothing (no effect) against each of the target's types. A
  monster's `affinities` (weak, resist, immune, absorb) are exceptions on
  top of the chart, like a boss immune to fire or a slime that drinks water.
  Damage events carry `damage_type` and `effectiveness` (a percent); a move
  with no effect is a miss with reason `immune`.
- **Statuses by type.** Poison and steel types can't be poisoned, and
  electric types can't be paralysed.
- **What the party learns.** Seeing a typed move land on a monster shows
  its type, and the chart fills in the rest for the command help. A scan
  shows everything.
- **Moving over.** Migration `ElementsToTypes` maps the old elements (bolt
  → electric, wind → flying, earth → ground, holy → psychic, the rest by
  name) in abilities, items, monsters and stored battles, so a battle in
  progress carries on. Re-run `bin/rails base_world:update` to get the Base
  World's own types, the Skeleton (dark) and the Nymph (water).

## Departures from the handoff

- **RNG.** The handoff says `Random.new(seed)`, but Ruby's `Random` can't
  expose its internal state as data. The resolver uses a 32-bit mulberry32
  whose whole state is one integer (`state["rng"]`). A battle can resume
  exactly from any persisted state, which is what the handoff is asking for.
- **Abilities take a list of effects** instead of one primitive, e.g. Bio is
  `elemental(poison)` + `status(poison)`. The list only draws on the closed
  primitive set, so the vocabulary stays closed.
- **Damage types, not elements.** The handoff's eight elements are replaced
  by Pokémon's type chart, less fairy and dragon (see "Damage types").
- **Buff/debuff `amount` is a percentage**, so it scales across levels.
- **`haste`/`slow` are statuses** that modify agi through `Stats::Derivation`.
  `blind` halves physical hit chance. `sleep` and `paralyze` skip turns, and
  a physical hit ends sleep.

## Not in yet (deliberately)

All the numbers are first guesses (§9.2) and will change in playtesting.
