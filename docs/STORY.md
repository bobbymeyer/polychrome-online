# Story: what to take from *Procedural Storytelling in Game Design*

A reading of Short and Adams (eds.), *Procedural Storytelling in Game Design* (2019),
chapter by chapter, for ideas that fit this game. This is a prioritized list, not a
contract: `docs/HANDOFF.md` still wins. Each item says where it came from (chapter
numbers), what it builds on here, and roughly what it costs (S, M, L).

What "fits" means here:

- **The GM keeps the improviser seat** (HANDOFF §1). The engine paces, offers and
  remembers; the GM says, rewrites or skips. Nothing below speaks for the GM unasked.
- **Pure where it can be.** Rolls, matching and pacing go in `lib/` over plain data with
  seeded RNG, like the resolver and the generators.
- **Worlds are live** (§9.8), and **places re-roll from their seed on every view**
  (`Location::Generation`). A generator change rearranges places already in play, so
  generator changes are opt-in template settings, or drawn after everything else (as
  locks are).
- **Omakase** (§10). Rows are JSON in the tables we have; no new gems, no editor until
  the shapes settle (ch. 28).

## Now: small, and they fix things that are thin today

1. **Forks that cost something.** Every room must carry a decision (§7), but a fork's
   "visible cost" is only a narrated line (`Location::Exploration`), and the costly way
   is picked at random. Give fork rows a real price, written the way a thing to do's is
   (`Pastime`: "pay 100", parts of a day) with costs from the one closed set (`Outcome`:
   a share of HP or MP, a fight), paid when the party takes that way, and make the
   costly way the shortcut to the boss or the side with the treasure. *(ch. 2, 20; M)*
2. **The game notices who the characters are.** Motive, origin, home town and ties are
   only read by the language-model prompts (`Drafts::Base`). Say so when a character
   arrives home ("Vivi is home."); show a tie to that player and the GM when the tied NPC
   is present or speaks; keep the motive on the player's "You" card. *(ch. 10, 21; S)*
3. **Townsfolk couplets.** A townsperson is a name, a title and a hook. Add a past line
   and a now line in the first person, from two tables that combine freely: "I lost my
   brother on the Barrow road." / "I'd give anything to see it opened." The now line can
   name something the party can deliver: an item (bringing it is a thing to do in that
   town, which the table can vote on like any other), or the nearest dungeon cleared
   (they're who greets the party when the town welcomes it back). Either is a deed, so
   the town thinks better of the party. *(ch. 3, 7, 22, 23; M)*
4. **The hundred-roll report.** The Gazetteer template page shows one example. Roll a
   hundred seeds and summarise: room counts, decision mix, how often each table row is
   drawn and which never are, placeholders ("Stranger 1"), locks dropped for want of a
   hiding place. View-only and pure; it tells a world-builder where their tables are thin,
   and it is how every later generator change gets judged. *(ch. 1, 4, 5, 16, 28; S)*
5. **Lines and veils for each table.** Only the world has them. Let a campaign add its
   own, from any seat, shown without the name of whoever added it, and send them to the
   draft prompts beside the world's. *(ch. 5; S)*

## Next: the foundations, then what stands on them

6. **The story matcher** (`lib/`, pure). The same mechanism kept coming up: tagged rows
   with fallback (ch. 4), lines gated between what the party knows (ch. 7), event
   requirements that chain through flags (ch. 11), descriptions from a world model
   (ch. 16), reactions (ch. 21). Ruskin's *Left 4 Dead* system (ch. 25) is all of them:
   facts about the moment in (the place, its mode and past, the time of day, who is hurt
   or home, clock fills, flags), every matching row competes, the most specific wins, ties
   go to the seeded RNG. Rows can write back to campaign flags, rule each other out
   (ch. 22), carry a little grammar (ch. 1, 16), and pass a word check against the
   table's lines and veils (ch. 5). A page lists every fact a writer can match on.
   *(M, and most of what follows gets cheap after it)*
7. **GM moves, on the one closed set of effects.** `Outcome` is already that set for what
   the party gains (field abilities, payoffs, things to do, scenes, clocks); fork costs
   add what it loses. Dungeon World's list (ch. 20) splits it into soft moves (words: show
   signs, reveal an unwelcome truth, offer an opportunity) and hard moves (damage, use up
   HP, MP, money or time, tick a clock, start a fight). Complications on a failed check
   and camp events draw on it. *(ch. 10, 20; M)*
8. **Fronts as Dangers, with omens.** A clock is silent until it fills. A front gets an
   impulse (what it wants) and moves; each clock segment becomes a portent, a step a
   little worse than the last (ch. 19's boiling frog); and each portent has signs, omen
   lines the arrival narration may carry, more often as the clock fills (ch. 4's
   Creepifier, ch. 20's "show signs of an approaching threat"). Written to fit whatever
   the table is doing (ch. 17). A first cut needs only a list of lines per segment; the
   matcher adds place and time. *(ch. 4, 12, 19, 20; M)*
9. **The moves panel.** When the table stalls or a check fails, the GM's panel offers
   what's live: each front's impulse, next portent and one move (soft and hard), a
   chain's next step, wants heard but not met, antagonists who got away. The GM picks one
   or ignores it. It mostly reads data we have. *(ch. 7, 10, 20; M)*
10. **Camp and road events.** Rests and journeys are one fixed line each. Events from a
    new table fire at those moments (never at random mid-scene, ch. 19), match on the
    party (motive, ties, who's hurt, clock fills), name who they matched, offer one or
    two choices made of the game's own verbs (fight, give from the bag, pin an NPC,
    travel; ch. 23) with moves from item 7 as their effects, and set flags that later
    events require, so arcs chain without planning (ch. 11). Each sets two things the
    table values against each other, not just HP against gil (ch. 19). They go to the GM
    as offers, like entrance lines. *(ch. 9, 10, 11, 19, 23; L)*
11. **Secrets as chains with clues.** A secret comes out all at once. Make it a few steps
    from vague to specific; the first is a question ("why is the mayor's lamp lit at
    midnight?"). Clues sit in rooms, townsfolk, items' pasts and codex pages, and each one
    found gives the next step wherever it was found (ch. 14). Lines, rumours and omens can
    say which steps make them make sense and which make them redundant, so nothing tells
    the party what they already know (ch. 7). Clues can disagree, marked with who says so
    (ch. 8, 18). *(ch. 6, 7, 8, 14, 18; L)*

## Later: good, but after the above

- **Fronts with a few possible truths.** A world's front carries two to four authored
  truths and a campaign draws one; the GM knows which. The same world plays differently
  twice. *(ch. 14; M, after 8 and 11)*
- **Families tell their own version.** History already records a public text and a GM
  truth; let the family's clues tell the flattering one and the rival family another.
  Townsfolk can belong to History's families, so a feud shows in the street. A motif per
  family (fire, the river, silver) colours its lines and heirlooms. *(ch. 15, 18, 24; M)*
- **Chapter titles and "Was it worth it?"** Key moments (a boss beaten, a place cleared,
  a clock filling, a wipe) give the campaign a numbered chapter the GM can rename; the end
  of a thread or campaign shows them, the deeds and the fates of the people met, and asks
  rather than judges. *(ch. 14, 19; S–M)*
- **Deeds leave names.** After a boss or a cleared dungeon, the table picks a name for
  the weapon or the place from three dealt, by vote, as "Where next?" does; rumours and
  the legends page use it. *(ch. 13, 15, 17; S)*
- **A town's hope.** Beside its view of the party: falls as a nearby front's clocks fill,
  rises when the place behind them is cleared; drives mood lines and whether services
  run. *(ch. 19; M)*
- **Write the missing line at the table.** When the matcher has only a fallback, the GM
  can write one there and then; it's saved with the moment's facts as its criteria.
  *(ch. 28; M, after 6)*
- **Coverage page.** The report grown into the matcher's test harness: slots with no rows,
  rows never matched, live draws beside the row editor. *(ch. 7, 16, 28; M, after 4 and 6)*
- **Rumours retold on the road.** A teller is added, then numbers grow, then details
  wander; a rumour about a place stays right about where it is. *(ch. 3; M)*
- **Arrival descriptions.** Generated towns have none. A short paragraph from facts (kind,
  terrain, mode, past, view of the party, time of day), seen through one of them per
  visit; flavour, never the only place a hard fact shows. *(ch. 16; M, after 6)*
- **Promises.** One at a time per player, offered from their motive and what's live;
  keeping it is said at the table and pays a little. *(ch. 10; M)*
- **Spreads.** Deal three to five rows from the world's own tables into named positions
  (what happened, what's happening, what it wants, what it will cost) for the GM to read.
  An improv tool that needs no language model. *(ch. 26; S, after 6)*
- **Absences in dungeon pasts.** A nursery in a manor whose history has no child; a
  portrait turned to the wall. *(ch. 18; S)*
- **Dungeon tuning.** Treasure and keys favour dead ends (ch. 2); deeper rooms lean to
  heavier groups with the boss's kind before it (ch. 1); hooks don't repeat across towns
  (ch. 1). Opt-in per template. *(S each)*
- **Background on screen.** A cast member's codex line beside their words when the GM
  speaks as them. *(ch. 6; S)*
- **Name lists by region.** For worlds with more than one culture. *(ch. 22; S)*

## Rules for writing, not features

- Say themes outright; the second read is a bonus (ch. 12).
- Pull, don't push: raise the question before the answer (ch. 18).
- Townsfolk traits are extreme and active, in the first person, a small story rather
  than an adjective (ch. 21, 22, 23).
- Two details beat five (ch. 3, 27). Specific beats varied: more variants can make the
  average blander (ch. 28).
- Omens and events are written to fit however the table got there (ch. 17).
- Keep previews to one line: a fork's cost, the odds by a Fight button (ch. 3).
- Describe generators honestly: "a reroll is a new seed" (ch. 5).
- The Base World's rows cover a range of tones, since the first world sets the style
  for every one after it (ch. 28).

## Left out

- Generate-and-test on seeds: only if the report shows failures (ch. 1, 2).
- Neural or Markov text, and sensors in the real world (ch. 17): wrong aesthetic, no need.
- Constraint solvers and tile layouts (ch. 1): the dungeon generator already does its job.
- A Book of Laws (ch. 19): the party doesn't govern; its lessons went into items 8 and 10.
- Hidden simulation of NPC needs (ch. 21): what players can't see isn't there.
