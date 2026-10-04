# JRPG Tabletop — Handoff

A multiplayer tabletop RPG with a human GM and JRPG mechanics. Rails app. One opinionated base world, architected so another author could build their own.

This document is the design contract. Read it before writing code. Where it conflicts with a shortcut, the document wins until Bobby changes it.

## 1. What it is

- A human GM runs a table of 3–5 players in the browser.
- The engine owns the rules (referee). The GM keeps the creative seats: author, narrator, improviser.
- Mechanics borrow from FF5 / Dragon Quest / Phantasy Star: pure turn-based battles, jobs, abilities, equipment. No ATB.
- Players and GMs read **archetypes** where the code says jobs (`Job`, `CharacterJob`, `jobs` tables, routes): every screen, message and error says archetype, archetype level, Archetype Compendium. This document keeps the code's word.
- No dice. Outcomes are computed deterministically by the engine and shown as results ("CRIT!"). Fairness comes from a deterministic resolver that is identical for everyone and that the GM cannot secretly tilt — GM overrides are explicit, logged actions.
- Ancestor: Neverwinter Nights DM Client (a human possessing a running module), not Roll20.

### Non-goals

- No AI GM. Automating the improviser seat makes it a video game.
- No tile maps, no tile movement, no pixel-art pipeline.
- No AAA animation. Motion is gestural.
- No second-author features (export/import, edition tooling) until there is a second author. Keep the seams; don't build the features.

## 2. Three layers, three tempos

| Layer | Tempo | Who | Contents |
| --- | --- | --- | --- |
| Setting (the books) | Prep, months | World-builder | Worldbook, Gazetteer, Bestiary, Encounter Tables, Job Compendium, Armory/Grimoire, Generator Tables |
| Campaign | Between sessions | GM as author | Pointcrawl instance, NPC/location diffs, party, flags |
| Session | Live | GM as narrator/improviser | Battles, chat, reveals, rerolls |

Everything is a row. There is no YAML world. The base world is seed data: the first `World` and its children. Greenware (`db/seeds/greenware/`) is a second seeded setting, written against the same books through the same seeder (`Seeds::Setting`): the proof that another author can.

## 3. Closed vocabularies

Three places where the engine holds verbs and the books hold nouns and numbers. World authors compose from these; they never extend them.

### 3.1 Mechanic primitives

Ability effects are a fixed set of named formulas with parameters. First set:

- `physical(power, hits)`
- `elemental(type, power, hits)`: the type is one of the world's
- `status(kind, chance, duration)`
- `heal(power)`
- `drain(power)`
- `buff(stat, amount, duration)` / `debuff(...)`
- `revive(fraction)`
- `escape`
- `cleanse(kind)`: cure one status, or every harmful one when no kind is named. Added when the base world needed cures (Antidote, Remedy, Esuna).

Plus targeting: `self`, `single_ally`, `single_enemy`, `all_allies`, `all_enemies`, `random_enemy`. Add primitives only when the base world needs one. No expression language.

**High is good.** Every die and every number the players read is big-good, little-bad: a d100 comes in when it reaches what was needed, a check adds its modifiers to the roll and has to reach a target, and no mechanic is ever roll-under. A shown roll is the honest die; what moves it is shown as steps, in order.

Damage types and skills are **not** in the closed set: they are the world's nouns, not the engine's verbs. Each world lists its own types (one or many; the first is the plain one), the chart between them, which statuses each shrugs off and the type of each terrain (`worlds.damage_types`, `worlds.terrain_types`). A battle copies its world's chart into its state, so replays stay exact when the chart changes. Removing a type sends its uses to another and drops monsters' affinities with it (`TypeChange`). Each world also lists its skills, each on a stat (`worlds.skills`); a job adds +15 to the ones it's good at (`jobs.skills`). The statuses, stats and passives stay closed: the engine has code behind each.

The effect library (`Battle::PRIMITIVES`) is meant to be broad, and flavoured by the world: damage (physical or typed, with bonuses against a status, type, the undead or bosses, recoil and grudge), heal (which hurts the undead), drain, status (including aggro, stop, berserk, confuse, charged, doom), buff and debuff, revive, cleanse, steal, scan, **away** (the user or the target leaves the field for some turns; Jump is one), shield, imbue, percent-of-HP damage and MP sap. An ability can cost HP and take turns to charge. The Grimoire writes tiered families (Fire, Fira, Firaga, Firaja) from one form. Outside battle, a job's **field ability** is a skill check the player asks for and the GM approves, with one of the game's outcomes on a success, once per rest (`FieldUse`); it rolls as any check does (`Campaign#check!`), and a check the GM calls can have an outcome on a success too.

Story tools kept small and pulp: a campaign can open with only some jobs and the GM grants the rest as rewards (`Campaign#grant_job!`); summons are small creatures from the Bestiary that come, act and go (the `summon` primitive), not epic set pieces; an NPC can be a recurring antagonist who fights as a Bestiary entry, gets away stronger, and is finished when knocked out (a villain from the setting's cast slips away the first time instead, and waits in their own lair's boss room); and any place on the map (a town, a dungeon, a landmark, the wilds) can switch into a prepared mode (the city burns) with shut services, its own music and trouble on arrival, while the world stays as it is (`MapNode#switch_mode!`). A mode can have its own picture, drawn from the place's Gazetteer image with the mode's words as one more layer (`ModeArt`). Pressure and prep: clocks (`Clock`) fill by hand or on rests, journeys, failed checks and new days, and can keep to the calendar's words ("each new day, on market day"); a full clock can set off a mode. What each event sets off (the rest's payday and clocks, the hours' modes and rumours, the new day's clocks and overnight) is in one place, `Campaign#happen!` (`Campaign::Happenings`), and nothing else calls those listeners; secrets (`Secret`) are written loose in prep and revealed however the table gets there, by the GM or an `uncover` field ability, and both feed the recap. With a language model set up, the GM can ask for drafts of secrets, clocks, scenes and modes, and world editors for descriptions, ability family names and a setting's types, skills and jobs (`Draft`); nothing is used until it is kept. A world is a setting as well as rulebooks: an atlas of named places and roads (fixed seeds, so a town is the same in every campaign; landmarks and wilds besides towns and dungeons), a cast, a codex with a players' side and a GM side, fronts dealt into campaigns, a voice with lines and veils, its own words over the game's fixed ones (money, HP/MP, stats, services, statuses), a calendar (`Pointcrawl::Calendar`, pure: its own parts of the day, some of them its night, making days; weekdays; months with their own lengths and seasons, making years; eras; and the date the story starts on), and origins for characters. New campaigns start with the atlas and cast. Campaigns keep time in their setting's calendar: days and its parts of a day, moved by journeys, rests (which sleep until the day's first part) and the GM. A place can also list things to do there (`Pastime`: an atlas place's for the setting, a map place's for the GM), each with when, how long, a price and what it does. The table picks one like a way on, pays, and the time goes by. What anything outside battle does is one closed set, like the battle primitives (`Outcome`: money, EXP, ABP, a rumour, rest, restore, raise, reveal, find, learn, sneak, safe road, uncover, story, and, aimed at something named, a place set in a mode and a fight): things to do, checks and field abilities, the archetypes' payoffs, a scene's ending and a full clock all give them. A scene (`Scene`) is a sequence of beats (`Beat`): who speaks and what they say, the stage behind them (a place, a panel generated for the beat with the place as its subject, black, or what was there), who stands on the stage (full body as their sprite, `Sprite`, else their portrait), a cue; the GM steps it on the Stage from the table or lets it play on, and its ending follows the last beat. A town's inn, temple and guild are things to do the town makes (`Location::Town#services_for`), and camp is one on the road (`Campaign::Services`); every night's sleep is `Campaign#sleep!`. A public clock filling stops the table with a card. A mode can come on by itself when the calendar says, in its words (parts of the day, weekdays, months, seasons: a place by night, in winter, on market day; an atlas place's night line becomes a "By night" one, for any place). Modes layer: a place is in the one set off at the table and every one the calendar has brought on, at once. A mode can shut services and the place's usual things to do, and have things to do of its own; what the modes a place is in say is heard on arriving there. A grant can go to one character instead, who awakens to the job (`Campaign#grant_job!` with `to:`): the job opens, they take it up, and the table sees it. A world can have its own battle rules on top of the engine's (`Battle::RULES`, carried in the battle state): One More, where a weakness or a critical hit knocks the target down and the striker goes again (at whoever is still standing and weakest to the move), and where the party has every enemy down, an All-Out Attack. Daily life pays off through the archetypes (`Job#payoff`, `Campaign::Payoffs`): the parts of the day spent on things to do are counted, and the next rest pays each character standing their archetype's way (money, EXP, ABP or a rumour).

### 3.2 Motion gestures

`bounce`, `shake`, `flash`, `fade`, `spin`, `lunge`, `pop`, `float`, `tint`, `slide`. Whole-sprite transforms only. Implemented as anime.js presets. Used for battle and for UI chrome (dialogue box, map reveals, cursors) so the whole app moves the same way.

### 3.3 Art

An enemy is an image. A player is an image. A map feature is an image. No part libraries, no rigs. Each book entry has an image slot plus a small variant recipe (tint/hue shift, scale, flip) so one image yields palette-swap variants.

## 4. Data model sketch

Every table that belongs to a world carries `world_id`. This is the only second-author feature built now.

### Setting

- `worlds`
- `regions`, `factions`, `lore_entries` (Worldbook)
- `location_templates` — town / dungeon / field archetypes; generator config (Gazetteer)
- `named_places` — fixed, hand-authored locations
- `monsters` — stat block, image slot, variant recipe, AI script (condition/action list), drop table
- `encounter_tables` — weighted monster groups by terrain/tier
- `jobs`, `job_learn_tables` — FF5-style: a type, job levels 1–100 on one ABP curve, the job level each ability comes at, equip permissions, innates. Each ability grows to mastery over the 40 job levels after it's learned (+50% power), gets +25% in the job that teaches it, and keeps its job's Str/Mag once mastered; job level 100 masters the job (`Stats::Mastery`)
- `abilities` — primitive + params + targeting + cost
- `items`, `equipment`
- `generator_tables` — name lists, NPC hooks, room templates, shop archetypes, building archetypes

### Campaign

- `campaigns` (belongs to world; reads its books live — see §9.8)
- `map_nodes` — type (town/dungeon/field/event), visible?, position, location ref
- `map_edges` — state (open/blocked/dangerous), encounter table ref, travel event
- `locations` — instantiated from a template with a seed; GM diffs stored as overrides on top of the seed
- `npcs` — instance of a generated or authored NPC; portrait image, expression set
- `characters` — player-owned; job state, stats, inventory
- `character_jobs` — job, ABP, level
- `ability_slots` — equipped cross-job abilities
- `inventories`, `equipment_slots`
- `flags` — campaign-scope key/value for the GM's own state (a choice's outcome, a count), never shown to players. What the party knows is one thing: its secrets, revealed (`Secret`), which a choice, a check's uncover, a cleared place or a leak brings out. Rumours are how news travels, not a kind of knowledge; the codex is the world's, not the campaign's.

### Session

- `battles` — state JSON, seed, status, turn index; each action is applied inside one write transaction (SQLite serialises writes, so two actions can never interleave)
- `battle_actions` — submitted actions, including `actor: :gm` overrides
- `battle_events` — resolver output log; the replay
- `messages` — speaker (polymorphic: Character | Npc | Gm), expression, body, scope (table/whisper)

Template vs instance everywhere: `monsters` → enemy instances inside battle state; `location_templates` → `locations`; `items` → inventory rows.

## 5. Battle resolver

Pure Ruby. No ActiveRecord inside it.

```
Battle::Resolver.apply(state, action) -> [new_state, events]
```

- `state` is a plain hash/struct: parties, enemies, turn order, statuses, RNG state.
- RNG is `Random.new(seed)` stored on the battle; RNG state advances deterministically so replays are exact.
- `events` are the contract with the view: `attack`, `damage`, `miss`, `crit`, `cast`, `heal`, `status_applied`, `status_expired`, `ko`, `turn_start`, `turn_end`, `flee`, `victory`, `defeat`, `gm_override`.
- Enemy AI: per-monster ordered condition/action lists evaluated by the resolver (FF-style: "if HP < 30% use X, else attack").
- GM override is an action type the resolver accepts and logs. It goes into the replay, never around it.
- Turn structure: Dragon Quest style — collect all party inputs for the round, then execute in speed order. Needs: input timers, "repeat last action" default, GM "auto" for an absent player.
- Stat derivation (base × job modifiers + equipment + passives + statuses) lives in its own pure module with the same test discipline as the resolver.

Test both modules exhaustively with RSpec. Property-style tests on the resolver (no negative HP, KO'd units never act, replays match) are worth more than example tests.

## 6. Battle presentation

- Server broadcasts the event list plus the pre-action state via Turbo Streams.
- A Stimulus controller builds an anime.js timeline from the events (gesture presets, damage numbers as created/removed text nodes) and plays it.
- State changes are applied to the DOM as events play; the final DOM state lands only when the timeline completes. This prevents the broadcast from spoiling the outcome.
- `timeline.seek(end)` = skip; `timeline.speed` = GM fast-forward.
- Reconnect / late join reconstructs from state, never by replaying events.
- Sprites are SVG groups or PNGs in the DOM. No canvas.

## 7. Other surfaces

**The Stage.** The game is shown on one 16:9 frame in the middle of every screen at the table, the same for everyone and the source of truth for what is happening: the scene on it, else the place's picture, the date, what's being said, and a battle when one is on (the map is the map page's). It takes the campaign's broadcasts, so it changes under everyone at once. The stage is display: interaction and personal management (moves, talk, the GM's tools, equipment, whispers) happen off it, in the columns beside it and under it.

**World map.** SVG pointcrawl. Nodes and edges are Rails partials; GM edits (reveal, add/cut edge, change edge state, drop encounter table) land via Turbo Streams. FF world maps are pointcrawls with walking theater; drop the theater.

**Locations.** Generated from `location_templates` + `generator_tables` with a stored seed; GM diffs are overrides on top. Two generators:

- Town: service roster (inn, shop, guild, temple), NPC roster with portraits and one-line hooks, shop stock. Rendered as a generated skyline from building archetypes.
- Dungeon: room graph (branching with loops; lock/key later), rendered as an SVG floorplan. A dungeon is a nested pointcrawl. Every room must carry a decision — encounter, event, key/lock, treasure, a fork with a visible cost. The generator's job is generating decisions, not rooms.

GM controls: reroll, pin, add hand-authored NPC/room, place boss, override stock.

**History and provenance.** Before play, a world can roll a pocket history over its atlas (`Generators::History`, written in by `Chronicle`). It is a seeded simulation, pure like the battle resolver: a few families across the places, over a century or so, in five-year steps. What it's made of is the world's own, like everything a generator draws on. Its lore (`Generators::Lore`) is a set of generator tables, edited like the rest: its families' trades and what they make, what its dungeons were (their rooms, heart and keepsakes, and the words in a name that give one away), how places fall, what people quarrel over, how they betray each other, what goes well for them, where they drown, how things change hands, and what's said overnight when someone is seen or a road is raided. A world without some of it has none of that happen. The Base World's are seed data, and worlds made before lore was theirs were given the same. It is written into the existing canon, not a parallel world:
- codex pages, with the truths in the GM notes;
- the living heads in the cast;
- a past on each place;
- running feuds as fronts.

Every generated place carries where it came from (`Generators::Provenance`):
- **A dungeon** was something (the Vell manor, sealed after the fire). Its rooms, boss and treasure follow from that, drawn on their own random stream so its layout and decisions never move.
- **A town** has a founder, old rivals and a running feud.
- **A shop's made things** have a maker and a previous owner.

The GM keeps families through rerolls and edits a place's past on the atlas; an edited past, like an edited page, is theirs, and the history won't write over it.

**The world moves overnight.** Each new day, a pure step over the campaign's map (`Pointcrawl::Overnight`, RNG in state like the resolver) decides what moved: clocks that tick now and then, rumours travelling a road a day, antagonists who got away wandering, caravans lost on dangerous roads and the prices that follow. The campaign applies it (`Campaign::Overnight`). The GM gets a private note; players only learn what reaches them as rumours. Kept secrets about a place sometimes leak there as rumours.

**Deeds and legends.** What the party does is history too. A deed (recorded by itself for an antagonist beaten or a dungeon cleared, or by the GM) starts a rumour carrying its sway, and each town the story reaches moves its view of the party, which sets its prices and, far enough down, whether it trades with them at all. The legends page puts the written history the party can know together with their own story.

**Clearing a place changes the world.** When a dungeon's boss falls (`Campaign#clear_place!`): its clocks stop, unless the villain behind them got away; its dangerous roads go quiet; the secrets it kept come out, as the thread to pull next; and the nearest town waits to welcome the party back, with a word from someone who lives there, a hook from someone else, and a good deed there: the town thinks better of the party, so everything it sells costs less (`Campaign#welcome_back!`). A town has one price rule for its shop and its inn, temple and guild alike (`Location::Town#price_here`): dearer after a lost caravan, cheaper for friends. Everything the party does goes through the ways on (`Campaign#take_way!`): travelling from the map, making camp, a thing to do, the table's vote.

**Chat.** Portrait + dialogue box. `messages` broadcast via Turbo Streams. GM has a "speak as" picker for any NPC (possession). Expression tag selects portrait variant. Whispers are scoped broadcasts. Open design question: sequential dialogue box vs simultaneous chat — leaning toward GM/NPC lines in the box and player lines in a side log.

**Books.** Each book is a Rails resource namespace. Each entry has two faces: a form and a rendered "page" (stat block, prose, cross-references, image). Cross-references between entries are the index.

## 8. Asset pipeline

- Book entries have an image slot (Active Storage) plus variant recipe. Nothing references pixels, so replacing an image is a file replace.
- Build phase: sprite rips as placeholders. They never enter a shared deploy or an export. Layout decisions made against them are provisional.
- Later: a ComfyUI pipeline. Entry fields → prompt template per asset class → LoRA-anchored generation → 4–8 candidates → rembg → candidate strip in the book panel → pick → store winner with seed and prompt on the entry. Design the entry columns (`image_seed`, `image_prompt`) now; build the pipeline later.
  - Built (step 9), with one change: the "prompt template per asset class" became three composed layers (world style, content-type framing, entry specifics), each able to add LoRAs, and the ComfyUI graph is built from the recipe rather than filled into a fixed workflow. The winner also stores its full recipe. Seed, prompt and recipe live with the subject's art notes, LoRAs and model in one polymorphic `Art` per drawn thing, not as columns on every table. rembg is a ComfyUI node named in config, skipped when none is set. Every image slot works this way, including speaker portraits (one per expression, with the expression as a last layer). See README "Art".
  - Rebuilt: each layer can also name a model (the lowest wins) and stack LoRAs in order, each with an on/off switch. How a model runs comes from its family in config (Anima by default; Krea 2, SDXL lineages, SD 1.5). The workflow is built per image against what the ComfyUI server reports installed, with the fewest nodes that do the job (no negative encode at CFG 1, the loader that matches how the model is stored, and so on). ComfyUI is reached over plain HTTP with optional token, headers or basic auth, so it can be anywhere. An optional OpenAI-compatible language model rewrites the subject layer in the style the model family reads best. See README "Art".
- Later still: human artists. The pipeline output is their brief.

## 9. Known problems, ranked

1. Scope — three products (game, authoring layer, asset pipeline) built solo. Mitigation: `world_id` everywhere, nothing else for second authors.
2. Tuning — closed verbs, open numbers; FF-style formulas are touchy and the job/ability surface is combinatorial. Budget playtest time.
3. Turn pacing — rounds wait on the slowest human. Timers, defaults, GM auto.
4. Dungeons without tiles — rooms must generate decisions or exploration is thin.
5. Dialogue box vs group chat — pick a model (see §7).
6. Animation/DOM race — see §6.
7. Stat derivation bugs — pure module, heavy tests.
8. Editions — decided: **worlds are live.** A GM develops their world as they play it, so editing the Bestiary changes live campaigns, on purpose. There are no world versions and no pins. What stays stable: a battle in progress (it copies what it needs when it starts), anything a GM has pinned in a location, and the people of a place the party has been to (it keeps the name tables it was rolled from then, so the innkeeper they met keeps her name; a reroll, or letting go of that change, takes the world's tables again). Forking is copying: a new world can start from another world's books. The seed never overwrites an existing entry; `bin/rails base_world:update` does, explicitly.
9. Turbo Drive vs persistent game screen — game is one long-lived page fed by streams; books use ordinary Turbo Drive navigation.

## 10. Stack

- Omakase Rails until it is painful not to be. Take the Rails 8 defaults and leave them alone until one of them actually hurts.
- SQLite for everything, including Solid Queue, Solid Cache and Solid Cable in production. Structured book data (stat blocks, effect lists, AI scripts) lives in JSON columns and is read in Ruby. Move to Postgres only when SQLite causes a real problem, like write contention or needing to run on more than one server. Not before.
- Hotwire (Turbo Streams + Stimulus), importmap.
- anime.js (MIT) — https://github.com/juliangarnier/anime
- Active Storage for images.
- RSpec.
- Later: ComfyUI — https://github.com/comfyanonymous/ComfyUI ; rembg — https://github.com/danielgaster/rembg

## 11. Build order

1. Resolver + stat derivation as pure Ruby with tests. No web yet. Prove a full battle replays exactly.
2. Books: Bestiary, Jobs, Abilities, Items as admin CRUD with page views. Seed the base world's first dozen entries.
3. Battle screen: Turbo Streams + Stimulus event player + anime.js gestures. One party vs one encounter, sprite rips.
4. Characters and jobs: creation, ABP, ability slots, equipment.
5. Chat with portraits and GM possession.
6. Pointcrawl map with GM edit tools.
7. Town generator, then dungeon generator.
8. Campaign layer: flags, diffs, pins.
9. Asset pipeline.

Steps 1–3 are the proof. If the battle isn't fun with a GM in the seat, nothing after it matters.

## 12. Conventions

- Resolver and derivation modules are pure functions over plain data. No AR, no I/O, no global state. Seeded RNG passed in.
- Events are the only contract between engine and view. Views never compute outcomes.
- GM power is never hidden. Overrides are actions and appear in the log.
- Book entries are descriptions/recipes. Rendering (image variants, generated locations) is derived and cacheable, never the source of truth.
- Prefer boring Rails. Reach for JS only in the event player and the map.
- Controllers only do CRUD. A verb is a resource that hasn't been named yet: "reroll a location" is `Locations::RerollsController#create`, "reveal a secret" is `Secrets::RevelationsController#create` (and concealing it is `#destroy`). Nested controllers live in a folder named for their parent, and load it through a concern (`LocationScoped`, `DraftOwned`, `ChoiceScoped`).
- A model that tells several stories tells them in concerns, one story each, in a folder named for the model (`Campaign::Shopping`, `Location::Exploration`). A slice's constants live in the slice.
- When the game says no ("the party can't afford that"), a model raises `Refusal`, and the person who asked sees it as an alert. `ArgumentError` means a bug, and crashes.
- The table hears the game through `Campaign#narrate`.
- A migration that removes or changes a column runs outside a transaction (`disable_ddl_transaction!`). SQLite rebuilds the table to do it, and inside a transaction it can't switch foreign keys off, so the rebuild fires ON DELETE actions on other tables. `spec/migrations_spec.rb` checks. New foreign keys stay plain; the models clean up (`dependent:`).

