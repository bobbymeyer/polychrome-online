# Design

The mechanics are JRPG. The presentation **starts** Swiss instead of SNES: it begins from what
Josef Müller-Brockmann might have done porting the game to modern screens. That makes it a
starting point, not a rulebook, and the game's needs come first. When play needs something the
Swiss defaults don't give (more colour for state, an ornament that reads faster, a box around
something), make the change on purpose and record it under "Divergences" at the end.

The stylesheet is `app/assets/stylesheets/application.css`, with the stage on top of it in
`stage.css` (see "The stage").

## The stage

The Swiss base was right but too still: clean enough to read, not alive enough to play. The
stage is a second layer, in the spirit of Persona's menus, that keeps the base (white paper,
black grotesk, the grid, red for game moves, grey for the rest) and adds attitude. It is a
deliberate divergence from much of what follows, and where the two disagree the stage wins.

- **Shapes.** Buttons, menu items, tabs, tags and banners are parallelograms (a 10px lean).
  Portrait plates and sprites get one cut corner. Rounded corners are still out.
- **Type.** Display type (h1, banners, damage numbers, names in the roster) is Inter at 900,
  italic, tracked tight. A page title carries a grey echo, offset 4px.
- **Tabs.** A section's heading is a tab in the page's accent colour, hanging from its 3px rule.
- **The masthead** is a thin black band fixed to the top of the screen, full bleed, with the
  palette as a stripe under it: the brand a logo, every other colour of that stripe (seven of
  its fourteen) in a 2:1 block the bar's full height, leant into a parallelogram, /// (the same on a transparent ground is the site's icon), the way around the game, and one
  item for you (your name; under it How to play, Sound, Accounts and Settings for an admin, and
  Sign out), or Sign in.
- **Ground.** A halftone falls from the top right of every page and fills the enemies' side of the
  battlefield; the party's side is a slanted grey wash.
- **Shadows.** Only hard ones, offset, never blurred: a focused field, the dialogue box. The stage's
  frame has none: a 3px rule round it and nothing thrown behind it.
- **Menus.** Every menu is a table of rows (below): the slabs are for single buttons. A game
  menu (`.play`) slides its rows in one after another when a panel opens, and its cursor is the
  red row with a black edge; a grey menu's cursor is a grey row.
- **Choices are tables.** Where the table picks one thing from a list (a vote, the ways on, the
  things to do here) the options are rows of a table, not slabs: one a row, 44px tall, a hairline
  between them, columns lined up (what, who picked it, what it costs or does). The whole row is
  the control: hover or focus fills it red (grey for a grey table), a click anywhere on it or
  Enter picks it, Up and Down walk the rows. Rows are rectangles, a divergence from the slabs,
  so the columns read.
- **Unavailable** things are hatched, not just greyed.
- **Battle.** The acting unit stands on a red slash. A target gets a red reticle that turns.
  Damage numbers are heavy italic, white with a black outline and shadow, landing big and
  settling at a slight tilt; heals are green. Status and crit popups are tags. Round numbers are
  small tags; Victory, Defeat and Escaped are a black slab thrown across the whole stage with a red
  (or black) underline. Ability names arrive as black tags from the left. Low HP blinks; an
  urgent timer blinks red.
- **The log** lives in a drawer on the right edge, closed by default, so the play area stays
  the play area. A tab in the page's colour (or L) slides it open over the page; Esc or L
  closes it. While it's closed the tab counts new lines and gives a pulse. At the table it
  holds the table's log; in battle, the battle's log with the table's beneath it. The GM can pin
  it (on a screen at least 1100px wide, where the three columns are): it stays open as a column beside the page, and the
  page makes room for it. On a screen 1440px or wider it starts pinned for the GM. Closing it
  unpins it.
- **Dialogue in battle.** What's said at the table reaches the battle: a GM or NPC line appears
  as the same speech box beside the commands, typed out, and leaves once it's been read.
- **Into battle.** When a battle starts, everyone at the table goes: on any game page of the
  campaign (table, map, a town or dungeon, the campaign page, a sheet), slabs of the palette
  sweep across the screen, the battle page loads under them, and they sweep off the other side.
  Nobody is pulled away mid-sentence: the wipe waits for the dialogue box to finish. Where you
  came from is remembered, and the battle's end offers the way back to it.
- **Bosses.** A boss fight's wipe is black and wine. The enemies' side of the field goes
  wine-dark. The boss's name is slammed across the stage on a slab in its own colour, tagged
  BOSS, then it has the first word in the dialogue box (its line from the Bestiary). This plays
  once per viewer, and only in the first round. On victory a second slab follows "Victory!":
  "Goblin Chief falls!". A boss sent off the field hasn't fallen: the second slab is the Turquoise
  Escaped one, "Goblin Chief got away!", and a fight nobody fell in ends on "They got away!" with
  no fanfare and no hop. A fight the GM calls off ends on an ink "Called off" slab, on every seat's
  screen at once: the results panel follows it as it follows Victory or Defeat. The slabs are thrown
  over everything on the frame, the round's rail included.
- **The field fits its frame.** Enemies share one row of the frame, sized to the room the row has:
  a lone boss towers, five share the width, and a name wraps under its sprite rather than widening
  the row. With the log pinned beside the fight on an ordinary desktop, the battle's head sits over
  the frame instead of beside it, so the frame keeps its width. On a phone up to five stand abreast.
  The frame leaves room under it for the commands, and the menu never scrolls the stage away while
  the stage is speaking (a boss's entrance, a line in its box).
- **Reactions.** A script's "when" rule fires out of turn with a word popped on the creature in the
  critical-hit style (COUNTER!, VENGEANCE!, LAST BREATH!) and a shake, then the move as any other.
  A summon called for no set time goes down with its summoner: the adds are the boss's.
- **Phases and telegraphs.** What a creature says as its rule fires is a beat in the stage's
  dialogue box, with its face from the field and a pop of its sprite: the warning before the
  gathered blow, read where the blow will land, typed out as any line at the table is. A boss with
  music of its own (a track from the world's book) plays it for the fight, and a form with its own
  changes the music as it comes. On a phone the phase slab and the epitaph fit the width, the name
  on two lines if it must, never clipped at the edge. A boss becoming its next form is a wine-red slab thrown the other way from the
  boss-down one, its new name across the stage, its line after; the board that follows wears the
  new form. The Bestiary page lists a creature's phases under its script, and a form says what it
  is a form of.
- **The battle's log reads like the table's:** newest line on top, the newest tinted. The player at
  the end of their rope is told so before it happens: a line under the round says an Attack may become
  their desperation move. The GM's folded controls stay as they were left through the panel's reloads,
  and a player who has left the page is "away" in the GM's rows, with Auto beside it.
- **Desperation.** When a character's desperation move comes, the stage stops for them: a slab
  in their colour cuts across the field with their sprite held large, their line in quotes and
  the move's name in heavy italic, white with a black outline. A power chord plays under it.
- **Why they're here.** A character's line sits under their name on the sheet, in bold
  italic quotes, and on their party card in grey.
- **Previously on…** A returning player gets a title card over the table: the campaign's name in
  display type, then the last session in short sections (the road as names joined by red
  arrows, battles, finds, what the party learned) and the last line said, in a speech box.
  "Carry on" closes it.
- **Choices** come up as a window with a red top edge under the dialogue: big italic options
  underlined in red that fill red when pressed, and who picked what in grey beside them. The GM
  sees "Settle on this" instead.
- **A check** takes the middle of every screen: the character, the stat and what it needs, then a
  heavy number spinning to a stop, then each modifier in turn as a chip (+12 Agi, +15 Knight) while
  the number moves by it, green up and red down, and the verdict stamped in green or red, with a
  jingle. Several go one after another.
- **The forecast** on the battle form is a tinted band with a heavy verdict word, coloured from
  green (Easy) to wine (Deadly).
- **A town's services** are panels with a 3px frame, one per building: a white bar with the
  building's name in heavy italic and a red marker, which turns black when open. The buildings
  in the skyline that house them outline in red on hover and open their panel.
- **Types** are slanted tags in their own colours (fire orange, water blue, ghost violet and so
  on): this is the one place the palette steps outside Vasakronan, because a type's colour is
  how players recognise it. "Super effective!" lands as a yellow outlined popup with a flash;
  "not very effective" is small and pale. The type chart is a grid of ×2 (green), ½ (salmon)
  and 0 (black).
- **Local co-op.** The shared screen goes edge to edge with no menus: bigger dialogue type, the
  join card (a QR code in a white frame and the code in heavy display type) and the party's HP
  down the side. The controller is one column of big targets: your name as the title, your HP
  bar, options and commands at least 52px tall.
- **The game's words** keep their JRPG names and explain themselves. A dotted underline marks
  one; hovering or tapping it shows a black card with the definition (and the nearest D&D idea).
  "How to play" in the top bar has the rules in plain words and every term together.
- **Rewards** get cards: "New ability!" and "Mastered!" tags over a heavy name, a hard yellow (or
  red and black, for mastery) shadow, dealt in one after another.
- **Job moments on the board:** a Jump leaves the top of the frame and slams back down, Cover and
  Counter get tag popups, Second Wind a yellow one, and the dice sit beside whoever they decided for.
- **The timing meter** is a black slab near the bottom: a striped bar, the mark in yellow, a red
  needle. PERFECT! lands in heavy yellow italic.
- **The table.** The dialogue is a speech box: a 3px black frame with a hard shadow and the
  speaker's name as a black tag on its corner. System lines are grey slanted slips.
- **Motion.** Everything you press answers: a nudge on hover, a squeeze on press, pages slide
  in, results land one after another. It is quick (about 120ms) with a little overshoot. All of it
  stops for `prefers-reduced-motion`.

## Sound

Sound marks the moments, not every click. The jingles are synthesised in the browser
(`sound.js`) from square, triangle and noise voices, in the spirit of the consoles the game
remembers. The melodies are our own:

- **Encounter:** a climbing figure over a pulsing bass, then a stab. **Boss:** slow steps down,
  a tritone. **Boss entrance:** one deep hit as the name lands, then silence.
- **Victory:** a leap up, a turn and a held top note. **Defeat:** down and down. **Level up:**
  a run up two octaves and a sparkle.
- **Key found:** a small bell. **Door opened:** a thud and a rising fifth. **Treasure:** four
  quick notes.
- **Confirm:** a soft blip on game menus and play buttons, and nowhere else.

Music is the world's own, a book like the others (Music): a track for each kind of scene
(field, town, dungeon, battle, boss), and any more for the GM to call by name. A track is a
file uploaded or a YouTube or Spotify link (music is made elsewhere, in baible). Each page plays its scene's track, crossfading as you move, and a scene without a
track is quiet. A linked track can't be fetched, so it plays in its own small player in the
page's bottom-right corner, kept across pages; the viewer may need to press it once. At the
table the GM switches everyone from the stage's bottom-left corner: another scene's track, one
by name, or silence; battles keep their own. A boss's entrance stops the music for its moment,
then the boss track starts.

Nothing sounds until the viewer has clicked or pressed a key (browsers insist), and "Sound
on/off" in the top bar mutes this device.

## Icons

RPG Awesome (Daniela Howe and Ivan Montiel; font under the SIL OFL 1.1, CSS under MIT), vendored in
`app/assets` with its licence: a glyph font of game things, drawn as one-colour marks, so an icon reads
at the size of a word and takes the text's colour. Used where a word would crowd: the table's three
views in the top bar are a player (party), the spawn point (stage) and speech bubbles (log), each
titled with its name for the pointer and the screen reader. An icon never stands where a word is clearer.

## Paper and type

- White paper with black type. There is no dark theme, and no rounded corners. (The stage adds hard
  shadows, a halftone and the palette.)
- One typeface: Inter, a grotesk. It is vendored as a variable font in `app/assets/fonts/` under
  the SIL OFL. Hierarchy comes from size and weight, never from colour.
- Everything sits on an 8px baseline. Body text is 16/24, h2 is 24/32 and h1 is 48/56 with tight
  tracking. Small labels are 11–13px bold.
- Type is set flush left and ragged right. Figures are tabular wherever they are compared.

## Grid

- The page is 12 columns with a 24px gutter, at most 1200px wide.
- Split screens use the columns: the table and the battle's lower half are 7 + 5, and the maps
  are 8 + 4. Below 800–900px everything stacks.
- Sections sit under a 2px black rule, not in a box (`.window`, `.panel`). Rows in tables and
  lists are separated by 1px grey hairlines.

## Colour

Polychrome is in colour. The palette is fifteen colours (below), and every colour on the stage
is one of them; type stays near-black on white. Colour does four jobs, and each job keeps
its own colours, so they never argue.

| Name | Hex | | Name | Hex | | Name | Hex |
|---|---|---|---|---|---|---|---|
| Sun Yellow | `#FCC010` | | Grey | `#DEDCDD` | | Steel Grey | `#627E8B` |
| Orange | `#F4971B` | | Greyish Green | `#9DBFAE` | | Dark Blue | `#4153A1` |
| Bright Red | `#E9473A` | | Green | `#8DC04E` | | Blue | `#438ECC` |
| Wine Red | `#CD2E55` | | Forest Green | `#13955F` | | Turquoise | `#1EB8D1` |
| Pink | `#F6BCD0` | | Dark Green | `#335F4B` | | Lake Green | `#088EA7` |

1. **Game moves are Bright Red** (Wine Red for its hover and for red text). This hasn't changed:
   battle commands and targets (the red reticle), travel, the ways on in a dungeon, Fight,
   joining a battle, Send, starting a battle, the dialogue's advance mark. When you add a
   control, ask whether pressing it moves the game. If it does, give it `play`; otherwise it's
   grey, and grey controls stay the Grey of the palette.
2. **Where you are.** Each book has a colour, and so does the table: Bestiary Forest Green,
   Compendium Blue, Grimoire Lake Green, Armory Orange, Encounters Dark Green, Gazetteer Steel
   Grey, Generators Sun Yellow, and everywhere else (campaigns, the table, battles) Dark Blue.
   It's the page's accent (`--accent`, set on `<body>`): section tabs, the current book in the
   masthead, the echo behind a title, the halftone, flash messages, link underlines on hover,
   and tints mixed from it.
3. **Who.** Every creature, job and character without art gets a plate in a palette colour,
   picked from its name (`plate_style`), so the Goblin is the same green in the Bestiary, on the
   battlefield and at the table. An author can choose the colour instead (the entry's Colour
   field). The palette decides whether its letter is white or ink.
4. **What happened.** State has fixed colours: HP bars are Green, then Sun Yellow at half, then
   Bright Red at a quarter; statuses are Poison Forest Green, Sleep Blue, Paralyze Sun Yellow,
   Silence Wine Red, Blind Steel Grey, Haste Lake Green, Slow Dark Green; heals are Green; a
   crit is a Sun Yellow tag. Moves announce themselves by kind: magic Dark Blue, skills Orange,
   items Green. Victory is a Sun Yellow slab, Defeat an ink one, Escaped Turquoise.

Places are coloured by kind: towns Orange, dungeons Wine Red, fields Green, events Blue. Rooms
by decision: fights Bright Red, the boss Wine Red, treasure Sun Yellow, events Blue, forks
Orange. In a town, the inn is Orange, the shop Sun Yellow, the guild Blue and the temple Pink, and
lit windows are Sun Yellow.

The battlefield is a stage in colour: the enemies on Dark Blue under a white halftone (each
creature with a hard black shadow, no outline), the party on a slanted slab of Sun Yellow.
The art is the show there. Enemies fill their side of the stage: the fewer there are, the bigger
they stand, from 176px (120 on a phone) up to 360px or half the screen's height, so a lone boss
towers. The party stands 96px (72 on a phone).

The masthead is black, with the whole palette as a stripe under it. Uploaded images are content
and keep their own colours.

## Geometry

Simple shapes carry meaning, and each one is explained in a legend next to the map that uses it.

| Thing | Shape |
|---|---|
| Enemy | Square with its initial and a cut corner, in its own colour, with a hard black shadow |
| Party member | Circle with their initial, in their job's colour |
| Knocked out | The same shape, outline only |
| Ready (input in) | Small Green diamond in the roster |
| Active unit | A slash under it (Sun Yellow for enemies, Bright Red for the party) |
| Town | Orange square |
| Dungeon | Wine Red triangle |
| Landmark (a lighthouse, a manor) | Steel Grey house: a square with a pitched roof |
| Wilds (a marsh, a sea) | Dark Green hexagon |
| Field | Green circle |
| Event | Blue diamond |
| Hidden place (GM only) | Dashed outline |
| Party on a map | Bright Red triangle pointing down at them |
| Open, dangerous and blocked paths | Solid line, dashed line, and grey dotted line with an × |
| Encounter, boss, treasure, event and fork rooms | Small square, large square, diamond, circle, and a branching line |
| Key room | A key, Lake Green |
| Lock on a path | A Wine Red padlock; hollow once opened |
| Costly way in a dungeon | Dashed path with a black diamond at its middle |
| Current room | The room filled Dark Blue |
| Resolved room | Its marker shown in outline |

No emoji or pictographic glyphs. An arrow (→) is typography and may follow a link.

## Motion

The gestures in HANDOFF §3.2 stay. `tint` is an inversion pulse, because a hue shift is
invisible in black and white. Banners are giant black type, set flush left on the stage.
*Divergence:* the round number is not a banner but a small black bar at the top of the stage,
shown briefly. Giant type every round covered the enemies and slowed every round; it is kept
for the moments that end a fight (Victory, Defeat, Escaped) and for GM overrides. The routine
auto for absent players gets no banner at all, only its log line.
Captions are black bars with white type.

## Motion with meaning

Motion only ever says one of four things, and each has one shape, in every world's words:

- **Enter:** something new is here. It slides in from the left, like a menu item (`.is-new`).
- **Change:** a value you were looking at is different. A number counts to its new figure
  (tabular, with a pale wash: red-pink down, green up); a bar eases to its new length and a
  ghost of the old length stays a beat longer, so a loss or a gain can be read as a length; words
  that changed get a yellow wash that settles. A clock's newly filled boxes pop in turn, and the
  last one shakes the dial.
- **Cause:** this acted on that. The battle's gestures, damage numbers and reticle.
- **Attention:** you're needed. The timer and low HP, which blink; nothing else idles.

**In battle, cause is drawn.** A move draws a streak from whoever makes it to whoever it lands
on (red for a blow, dashed turquoise for an art, green for mending, violet for a drain), one per
target in turn. The round's order rides a rail over the field: a plate per unit, lifted red while
they act, struck through once they've gone, a yellow "again" plate for a second go (haste, One
More), faded for the fallen. What lasts on a unit is on its badge with its count (turns left, a
barrier's points, a blade's type), and a buff is an arrow with the stat's word in the world's own
vocabulary; a guard wears a bracket before the party, a charge glows, a barrier rings the sprite,
a doom underlines the name. Each party member's plan is a tag on them and in the roster ("Chip →
Slip Hound A") from the moment they choose, so the table sees the round form. When the round ends,
each roster row shows its net (−84, +25) and a line under the field says what the round came to
("Round 3 · Rook dealt 84 · Pim healed 25 · Slip Hound B fell"), until the next round starts.

**Before you commit.** In battle, the move under the cursor lights what it would reach on the
field (every enemy, the whole party, yourself) with a dashed outline, and a target the party knows
to be weak to it says "Weak!" in yellow ("Resists" the other way), from the chart and what they've
seen of its types, never more. At the table, a way says what it sets off under its name: a thing
to do its outcomes in the world's words, a night the clocks it ticks, a road the clocks a journey
ticks. A clock shows the box it's about to fill by itself as a dashed one. **Arriving** somewhere
is a card over the table: the place's kind, its name at display size, the modes it's in and its
line, held for a few seconds (`arrival` cue). **Settling a choice** is the same card: "The party
chose" and the option at display size (`chosen` cue). **The Now band** wipes across in the new state's
colour when the table's state changes (ink, red for a fight, blue for a choice), and the party's
marker on the map hops to where it went rather than reappearing. **Pressing** anything presses
it: the lift on hover, a push on press, a red slab of focus; the vote's options wear the pickers
as chips that pop on, with a bar of each option's share so far.

The live panels say it themselves (`motion/changes.js`): a view marks what matters with
`data-change` (number, bar, text, list, clock; keyed by `data-change-key` where order can move),
and whenever a panel is replaced by a stream or a page is morphed, each mark is compared with
what it said before. A number keeps where it came from in `data-changed-from`. Reduced motion
keeps the facts and skips the movement. The tokens are `--t-enter`, `--t-change` and `--t-count`.

## Play

The Swiss surface still has to play like a JRPG. Anything a player does in a turn works from the
keyboard, a mouse or a finger.

- **Command menus** (`menu` Stimulus controller) are pick tables with a cursor: the battle's
  commands, items and targets, and the seats, use the same rows as the table's votes and ways,
  with the MP, the count left, "Won't work" or "Weak!" in the cost column. In a game menu the
  cursor is the red row; in any other menu it is grey. The whole row is the control.
  It follows the arrow keys and the mouse. Enter, Space or Z chooses, and Esc, X or Backspace
  goes back. 1–9 picks an item directly. Movement wraps around the menu, and the cursor
  remembers where it was when the panel reloads.
- **A help line** under the menu says what the cursor is on: the target, the effects and the MP
  cost. While you pick a target, it shows an ally's HP, or an enemy's level and the affinities the party has found out (by hitting it, or with Libra; the campaign remembers them). A command you can't use stays
  selectable with a dashed outline, and the help line says why it's unavailable.
- **Targets** light up on the battlefield (a red frame) as the cursor passes over them. While
  you choose, the units themselves can be clicked.
- **You** are marked with a small black "You" tag on the field and in the roster.
- **Playback** is skipped with Enter, Space or Esc as well as the Skip button. **Dialogue**
  advances with Enter, Space or Z when you aren't typing, and with Esc at any time.
- **One screen:** on a laptop the field, the party's HP and MP, and the commands fit together.
  When your turn starts below the fold, the menu scrolls into view.
- **Touch:** menu rows are at least 48px tall and buttons at least 44px on coarse pointers. The
  keyboard legend is hidden on devices without hover.
- **Won't work:** when what the party knows of a target says a move can't touch it (the chart's
  no effect, or an absorb), the target says "Won't work" and the help line says why. It never
  tells more than the party has found out.
- **The clock is fair.** A battle's first round starts its input timer only once every player
  still standing in the fight has pressed Ready, or the GM has put them on auto; until then it
  says who it's waiting for. A character who is KO'd comes into the fight KO'd: their player
  watches, and a raise brings them back in. A player's idea waiting for the GM's ruling stops the clock. At ten seconds left,
  a phone buzzes and the page blips once.

### The first hour

- **The campaign page is the lobby**: the way to the table, the party, the cast, the invite, and
  nothing the party does. A rest, a battle and the bag spent happen at the table; the bag is
  stocked in Prep; the fights are kept on Legends with the rest of the party's record.
- **Prep is two tiers.** This session on the page: Scenes, then Clocks beside The moment. The
  reference behind one row of tabs under them: Secrets, Deeds, Rumours, Flags, Bag, with Changes
  to places a link beside them; a link into one (#secrets, from the table) opens its tab. Maps
  stays its own page, since it's another kind of editing.
- **Invites.** The campaign page has an Invite players panel: a link, its code and QR, and who
  has sat down. The link lets a friend pick a character the GM made or make their own (name,
  job from cards, motive) without an account. The shared screen's QR code is the same link with
  `?view=controller`, so a phone scanned at the table becomes a controller.
- **Your campaigns only.** The home page lists the campaigns you run or play in. An admin sees
  everyone else's below.
- **A first session.** Until the table hears its first line, the GM's campaign page lists the
  steps to a first session, crossing them off as they're done.
- **Setting out.** A new campaign starts in its setting's first town, with three Potions and a
  Phoenix Down. The GM sees how a fight is likely to go beside every Fight button.

### What you can do now

A player's table offers what they can do at this moment, and nothing else up front:

- **Moves follow the table's state** (the Now line's `data-state`). In a battle the moves go: the
  Now line has the way in. With an encounter waiting or a vote open, only the vote and talk
  are left. In free play: the ways on, the things to do here, the field ability, and talk.
- **The field ability is a row**, in the same table as the ways and the vote's options: the
  ability's name as the row, its skill, "once per rest" and what it does as the note, "ask" at the
  end. Used, or asked for and waiting on the GM, it's a greyed row that says so.
- **A move you can't make isn't offered.** A used field ability, or one asked for, is a line
  saying so ("Pick Lock: used. It's back after a rest."). Things to do the purse can't pay for,
  and doors still locked, aren't shown to players.
- **Talk is a button**, "Say something", that opens the box (and its To and Expression).
- **What you look up is in tabs**: Party · What we know, closed until pressed, one at a
  time. The Party tab says "hurt" or "someone's down" without opening; What we know appears
  once there's something to know, and holds only what moves: the public clocks still running
  and the questions the party is asking (a secret's clues so far). What it has found out for
  good is Legends' ("What they found out"), said once in the log as it came out; the recap draws
  from the same secrets. Your own HP stays in the "You" line.
- **Seating happens at the door.** Arriving at the table with no seat, the first thing under the
  Now line is your own way in: "Sit as Lenna" in red if you have a character here, "Sit as Game
  Master" if the campaign is yours; the characters nobody plays wait behind "Someone nobody
  plays" (sitting as one claims it), and nobody else's character is offered. The account menu
  says "At the table as Rook" and keeps "Stand up"; with no seat it points at the table. The
  campaign's menu keeps "Previously on…".

The GM's table works the same way:

- **The Now line is the GM's prompt**, with the moves for what's happening: in free play the
  controls row (Talk · Move · Do · Scene · Check · Fight · GM: what kind of moment
  this is, and what comes to the table for it); with a vote, "Settle it ↓"; with an encounter,
  "Fight or wave it off ↓" (to its panel, where the prelude can still be edited).
- **A battle is called at the table.** Battle puts a short setup under the stage: what they face
  (monsters and counts, or an antagonist), who fights (the standing pre-checked), the forecast as
  it changes, and Start; the name, the timer, the seed, where, and whether the party can flee wait
  behind "More" with sensible defaults. There is no battle form anywhere else, and calling one off
  is on the battle page, where the GM already is.
- **The rest of the tools wait behind "GM tools"**, a button on the Now line after Battle, always: Moves, and More (grants, music, the
  shared screen). Clocks and secrets are Prep's, not the table's: the Now line says when a clock
  is one tick from full, in red, with the way to Prep. Time passes where the day is spent: "Let
  time pass" is the last row of Do, beside the pastimes and Make camp, and nowhere else (a
  journey takes its road's time by itself). What
  needs an answer now (everyone down, a field ability asked for) stays out in front.
- **What the GM looks up is in tabs** under the tools: Party · What they know.

The shared screen keeps its panels: it's watched, not played. The stage-only view keeps nothing but
the frame (see "The Stage").

### The Stage

The game is shown on one **Stage**: a 16:9 frame in the middle of every screen at the table, the
same for everyone, and the one source of truth for what is happening. It takes the table's
broadcasts, so it changes under everyone at once and nobody refreshes to see it.

- **What it shows** is the scene: a beat's backdrop and figures while a scene is on, else the
  picture of the place the party is in when it has one, else plain paper; or the map, when the GM
  shows it (the Map switch on the place's tag, or by calling Travel, which puts it there). Travel
  from here is made from the Controls; travel anywhere is asked from the map.
  When sits in the top-right corner as one line straight on the picture, with no plate round it:
  the day clock and the part of the day as a label in that part's colour, one shape with one outline
  (the part it is now points right, into the label, so the slice runs into it), and the day at the
  same size, black on white in a slanted segment carrying on the label's border; the days left on
  public clocks under it, each its own white slip. Where (the place, and the room in a dungeon) is
  a tag in the top-left corner, across from when. What's being said plays along the bottom, in the
  dialogue box.
- **A scene plays on the same frame.** While the GM has a scene on the stage, its step is what the
  frame shows: the backdrop (a place's picture, a panel uploaded for the step, or black) fills it, the
  map steps aside, and whoever stands in the scene is along the bottom, left and right, full body as
  their sprite with their feet behind the dialogue box (as on a visual novel's stage), or as their
  portrait just above it until they have one; the speaker lit and a step larger, the rest dimmed. The
  line plays in the dialogue box as any line does. Starting a scene only changes the stage: no title
  card, nothing said on the Now line, which keeps the controls. The GM steps the scene line to line
  from the stage's corner tag (the beat count, Next in red, Play on or Pause, and ×, where the
  Map/Place switch sits otherwise), or lets it play on; the changes between lines (a backdrop, someone entering or leaving, music,
  an effect) are made on the way, so the table only ever stops on something said or asked. Each change
  comes on with the line after it, with its own transition: a quick fade (300 ms) unless the step says a
  slow one (1.4 s), a slide in from the figure's side, or a cut; someone leaving goes out the same way.
  A change plays once: a refresh of the stage doesn't replay it.
- **A scene is built step by step** on its page in prep. A new scene asks for a name and nothing
  else, and opens on the steps; the script box is folded away as a shortcut, there for a play's worth
  of lines at once. The page is a column of steps, each a small form of
  its kind, with a coloured kind tag at its left edge (ink for a line, red for a choice, and a grey
  for each kind of change) so the script's shape reads from the margin: speech, then a change, then
  speech. "Add a step" after any step opens a row of the six kinds. Beside the column the step
  chosen is previewed on the same frame as the table's, a change shown as the stage it leaves
  behind. The preview plays: the line types out as it will at the table (click to finish), a bar
  under the frame steps Back and Next with the count between, and "Play from here" runs the scene
  on at reading pace, a change passing in a beat, until a choice, where the table would decide. An
  empty scene shows the black stage with the invitation to add a step on it. Effects are a placeholder: a name on the step, nothing played yet.
- **A battle plays on the same frame**, on its own page: the field fills it, the party's roster is
  a band along its bottom, the round's rail along its top, the round's tally right over the
  roster (seated on its actual top, however many rows it has), and the lines said in the fight
  play over it as at the table.
- **The stage is display, and the view switch.** Interaction and personal management (the
  moves, the talk box, the GM's tools, what you look up, equipment, whispers) happen off the
  stage: in the columns beside it and under it. Two things on it are pressed, both about where to
  look: the place's name on its tag is the way into the place (its page), and beside it the GM's
  Map or Place switch puts the map on the stage for everyone or takes it off. There is no "Visit"
  or "Show the map" button anywhere else. On the map the GM presses a place for Go and Ask the
  table, with the journey by road; a corner button asks about anywhere on the map.
- **Stage only.** For a TV at the table or a stream on a call, `?view=stage` shows nothing but the
  frame: on black, as big as the screen allows, with no top bar, log, panels or caption, and a
  spectator's view of it (no GM secrets on the TV). The lines still arrive, unseen, so the moments
  they cue (a check landing, an awakening, an arrival) play on it; a battle takes it over the same
  way. "Leave the stage" shows in the corner when the mouse goes looking. The GM opens it from
  the shared-screen setup under More.

On a desktop (1100px and up) the page has no measure: it takes the whole width, and the screen is
three columns with the pinned ones on the far edges:

- **Left, on the edge: who's here.** What you look up: Party · What we know, the party open, and
  in the party your own row first, marked "You" (name, level and archetype, motive, HP and MP,
  the name a link to your sheet). There is no separate card: one list, you at its head.
- **Middle: the stage, first and sacred, and under it the Controls.** Nothing sits above the
  frame but the top bar, and nothing pushes it: everything that is done at the table is in one
  region under it that scrolls on its own. The Controls are the Now line, then what this seat
  does about it: a player's moves (the vote, the ways on, their field ability, talk), or in
  their place the GM's tools (what needs an answer first, then Scenes, Check, Clocks, Time,
  Secrets, More) with the GM's ways and talk under them; a viewer with no seat finds Take a seat
  there. Nothing else lives in the middle: the seat and "Previously on…" are the top bar's, and
  the last lines said are the log's. The frame fits the screen without scrolling: as wide as
  the column allows, or as tall as the room under the top bar less two fifths of the screen for
  the Controls, whichever comes first, always 16:9 and never narrower than 480px. What doesn't fit
  under it scrolls, and a wheel anywhere in the column scrolls it. The dialogue box and the
  date plate are sized to the frame, so a small frame keeps a small box.
- **Right, on the edge: the log.**

The log pins: a column on its edge, or folded to its tab and opened when pressed, as you left it
in this browser. The left column is always there. On a phone it's one column: you, the stage
(4:3 there, so the words along its bottom have room), the Controls, then the party; the date sits
under the frame.

### The table

- **Now, in one line.** Under the header, a strip says what the table is doing and whose move it
  is: a battle ("A battle is on: …", with the way in), else an open choice and who has picked and
  who still has to, else whose floor it is ("The GM has the floor" for players). For the GM in
  free play the strip is the controls row and nothing else: no "Now" label and no sentence,
  since the pressed control already says what the moment is and the panels below show what came
  of it; only a clock one tick from full gets a line. A battle goes red and holds everything
  else: an open choice greys out with "On hold until the battle is over", and can't be settled.
- **Who picked, and who can't.** The Now line names who has picked and who still has to, and says
  "Nobody plays Aoi" for characters with no player, so the GM doesn't wait on them; the GM's
  choice panel counts the picks ("1 of 3 players have picked").
- **Who is here.** The party panel says who plays each character, or "unplayed", and
  beside a player a dot: filled "here" while they have the table or a battle open (a heartbeat
  every 20 seconds), hollow "away" a minute after it stops.
- **What only the GM sees is marked.** The GM's tools have their dashed tag; the map's legend has
  "Hidden from the players"; and "The party knows" says "Everyone at the table sees this" to the
  GM.
- **A player's moves sit together** in the Controls under a red "Your moves" tag: the vote, the
  ways on, their field ability, then talk, in that order. The talk box says who hears it
  ("Everyone at the table hears it, said as Hoshi. Whispered, only the GM does."); To is two
  chips, Everyone and The GM.
- **The GM's speaker follows the scene.** The talk box has no "Speak as" select: a row of chips
  says who, the Narrator and whoever stands on the stage, with the scene's current speaker
  pressed (the box fetches itself again as the beats move, unless something is typed). A line
  that starts with a name and a colon speaks as them wherever they are, "Cid (happy): …" with
  the face, "Narrator:" for the narrator, the same grammar as a script. The speaker the GM last
  used stays pressed for the next line.
- **A whisper is done to a person.** The GM's "To" select is gone: beside each played character
  in the party panel is "Whisper", and the talk box then says "Whispering to Rook, and nobody
  else hears" with Everyone a press away. The whisper is one line; the next goes to everyone.
- **You, on the left.** Your own row heads the party list, with "You" on it; the table is
  refreshed in place as the game moves, so the row is marked again after each refresh (you_controller).
- **A service is a row**: its name, under it its kind, keeper and what it does, and in the cost
  column what it offers and costs ("Rest the night · 75 yen", "Buy and sell", "Shut"). The inn,
  the temple and the guild link to the table, where they're done; the shop opens under the list;
  the GM's pin is the last column. The place page's header keeps one button (Open the table):
  Reroll and the world's tables gather at the bottom under the GM tag, with the modes.
- **Lines and veils once per context**: at the table, where they're drawn; on the join page,
  before sitting down; on the world's page, as the setting's own. Not on the campaign page.
- **The talk box is the box first**, then one line under it: As (or To) as chips, the face as a
  plain select, Send at the end, and a help line that says what each does. No fold for the face.
- **Grants go to one or to all**: "The party (everyone)" is the first choice of who gets EXP and
  ABP, and each gets the same.
- **Time passes a part of the day at a time**: "Let time pass" is the GM's last row of the Do
  table, costed "a part of the day" like the pastimes above it, and the only row when there is
  nothing else to do here. A journey takes its road's time by itself; a rest sleeps the night.
- **The scenes called to the table** have a live search above them, and a played one is ticked
  (✅) before its name.
- **The battle setup starts with one monster**: "+" on the first row adds another, and each added
  row carries "−" to take it out (`rows_controller`); the rows are numbered again as they go.
- **The stage never changes size for what's under it.** In one column (under 1100px) the stage's
  column is as wide as the page whatever panel is called, and the frame measures its top again
  after anything that could move it (fonts, a notice, a panel replaced), so Travel, Scene and the
  rest leave the frame exactly where it was.
- **Help lines** (`help_controller`), not standing hints. A panel gets one grey line under its
  controls; the row, button or field under the pointer or focus fills it from its `data-help`,
  and otherwise it says the panel's one standing word, or nothing. The battle's command menu had
  this first; now the ways, the party's clocks, the door, the GM's check, grants and time, the map
  editor's panel, the services and people of a place, the shop, the battle setup and the sheet's
  sections (stats, gear, skills, mastery, archetypes) all do, and their paragraphs are gone.
- **A long sheet keeps its section links on screen**: stuck to the top, and on a phone on one line
  that scrolls sideways, fading at the edge where there's more.
- **Dialogue on the stage.** What's said plays along the bottom of the stage, over the scene or the
  place; the party's HP and MP are in the left column, and follow battles and rests live.
- **The log is the record.** What's said plays on the stage and lands in the log on the right;
  nothing repeats it in the middle. A whisper to you pops up for a moment.
- **A phone controller** shows your own character's check and field rolls, and in battle a
  ticker of what just happened on the screen everyone's watching.
- **"Previously on…"** opens by itself only for a session that's over, not the one being played.
- **Only what is in context is on the screen.** The Controls follow the table's state: in a
  battle, nothing but the way to the battle page (the fight's controls are there and only there);
  with an encounter or a choice open, the GM's tools fold behind "GM tools" and a player's field
  ability waits; while a scene is on the stage, a player's ways and ability wait too, and the GM
  has the director's buttons. Travel is the Controls' (Where next?). The battle page has no
  campaign chrome but its name, and talk is a press away.
- **The controls row is a strip of the spectrum.** The GM's controls, one short word each (Talk,
  Move, Do, Scene, Check, Fight, then GM) are short rectangles, not slabs, each in its own
  colour from the top bar's stripe (yellow, orange, green, wine red, blue, turquoise, and steel
  grey for the tools), running into the next with no gap, so the row reads as one band like the
  stripe above it. The one called is black with white bold text; one the table can't use yet
  (Travel with no road, Battle with no party) is hatched. It hugs the top of the column under the
  stage, edge to edge, with one rule above it (between the stage and the actions) and none below:
  what follows draws its own top, and the folded GM tools draw nothing. The panels it calls up
  (the ways, the things to do, the scenes, the check, the battle setup) have no heading of their
  own: the pressed control is the title. A divergence from the slabs, kept to this one row.
- **What the GM calls is the GM's moves.** The controls row on the Now line is the one switch:
  Talk puts the GM's talk box under the stage (their composer, and Whisper beside each character);
  under any other control it's away, so what's under the stage is only what the moment is for. A
  player's "Say something" is always there: talking needs nobody's say-so. Only a battle manages
  it, where Talk is a row of the command menu that opens the composer under the field, so saying
  something is one press like any command, and the command chosen stands. Travel and Things to do here put the ways there for
  everyone; Scene puts the scene list there and Check the check form, for the GM, in the same place a player's moves go,
  so there is one spot to look at whoever you are. There is no tab strip for these. What's left
  (Moves, and More: an archetype to grant, EXP and ABP to grant) is one more control on the
  strip, "GM tools" after Battle: called, it replaces what's under the stage like the others
  (players get nothing under it), one tab at a time; the
  open tab is ink, and the tab the GM had open stays open, per campaign, in this browser. What needs an answer now (everyone down, a
  field ability asked for) sits in front of it. On a phone as the GM's remote, the same comes
  after the play.
- **One list of ways while the party votes.** With a Where next? open, the GM's vote has each
  option as a row, who picked it, and Settle beside it; under it the same places are a small row,
  "Or go straight there, without the vote" (going now ends the vote), not a second Where next?.
- **A character's sheet is two columns on a wide screen, one section at a time.** The section links run
  along the top and stay there, as tabs: only the one pressed shows (the pressed link is ink), and a link
  with the section in its address lands on it. Who they are (portrait, name, their line, level, archetype,
  HP and MP) is a column on the left that stays put beside whichever section is open. On a phone it is one
  column, the links first. Without the script every section shows, one under another. Their look
  (the portrait uploads and the sprite) is a section of its own, "Look", for the GM and the
  character's own player, not a stretch of the edit form.
- **Narration is only as tall as its words**: with no portrait to make room for, the dialogue box
  doesn't hold a speaker's height open under one line.
- **A place's page is the place first.** The GM's controls for it (modes, rename) come after it,
  under the dashed "GM · only you see these" tag. The maps page's panel lists the ways from where
  the party is one to a row ("To Platform Zero / Dangerous road · Undertow Platforms") under "Go
  from here", and says a path takes the party along it now.
- **Going straight there asks first** for a dangerous road or a night, since one click moves the
  whole party.
- **Inside a dungeon, the stage's map view is its floorplan** (and the maps page has it under the
  map): every room and what waits there for the GM, only what they've seen for players. The GM's buttons for the rooms say what's in each
  (encounter, treasure, boss, done). Room names wrap onto up to three lines in their boxes.
- **A mode across the map is said once**, under it ("By night: across the map."), not tagged on
  every place; a place's own tag, in red, is for what's different there.
- **A map is a picture with the pointcrawl drawn over it.** The sheet is 16:9 like the stage it
  fills: the painted land (or plain paper until there is one), roads as one smooth ink line bent
  through their waypoints, places as their shapes with names in white-stroked italics so they read
  over any picture, a child map as a folded sheet, the party as the red marker. The maps beside it
  are black bands along the edges by direction, split between the maps that share an edge, and
  "↑ Parent" is a white chip in the top-left corner; the map's name sits in the bottom-right. The GM
  steers everyone by pressing those; a player's press browses their own frame only. In the editors
  the same sheet has handles: bends as white dots, places and maps draggable, empty ground clickable.
- **The party's story on the Legends page** has its fights (as the table heard each end:
  "Undertow Platforms: Victory! 70 yen…") and what it chose together ("Chose: Refuse."), beside
  its deeds and the rumours it heard. Where it went is the road, not the story.
- **Choosing a first move is being ready**: the Ready button says so, and goes once you've chosen.
- **Guests play; accounts make games.** Someone in by an invite with just a name isn't offered
  "New world" or "New campaign", and is turned back if they go there.
- **High is good, everywhere.** Every die in the game is read the same way: a big roll is good
  news and a small one bad, for the party and for its enemies alike. A check needs its total to
  reach a number ("needed 66 or over · rolled 43 +12 Agi +15 Knight = 70"), on the card and in
  the log alike, and a battle's dice come in when they reach what was needed. Nothing is ever
  "under". The GM's check form has "Everyone standing" over the names.
- **Things to do here get wide buttons** under Where next?, so "Wait for the train that isn't
  there (until day, tomorrow)" reads on a line or two; the roads keep their narrower ones.
- **A rolled encounter is what's happening now.** The Now line says "Encounter! 2 × Empty
  Uniform." and who calls it, and nobody goes on (no ways, no suggestions, no travel) until the
  GM fights it or waves it off.
- **Names on the map fit on a phone**, where they're drawn bigger: a place near the map's edge has
  its name run inward from it, and names are placed (under their place, or over it) by the room
  they take at the phone's size, so they clear each other there and everywhere.
- **The shared screen sends the table to their phones** ("Pick on your phones"), and its right
  edge stays clear of the log's tab.
- **Pictures come last.** A place's mode pictures are uploaded in a closed panel at the bottom of
  its page. The place comes first. Pictures are made outside the game (baible) and only uploaded
  here, so no page has a studio, a candidate strip or a prompt.

### Battle, at a glance

- **The round, and what its clock is for.** A player's command panel says "Round 2 · Choose
  before the clock runs out, or you Attack" (or "… Fire again (or Attack, if it can't)" after
  a spell), until they've chosen.
- **The GM's panel says who the round waits on**, by its clock ("Waiting on Hoshi."), and each
  side is a list of one-line rows, not a table: the name, HP and MP, what's on them, and for the
  party who chooses, with one button only when it matters: "Auto" while a player holds the round
  up, "Hand back" while auto is on, "Send off" for a guest. Auto is one thing, this round and
  the rest, so the GM never picks between two kinds of it.
- **A ruling is three fields**: what they roll, how hard, and what happens if it works. How
  much, a type, a status, on whom, and the two lines the table hears wait behind "More" with
  their usual answers, so most rulings are one press.
- **The sheet is six tabs at most**: Stats, Gear (equipment, then the bag's items to use), Abilities,
  Skills (with mastery under them), Archetypes, and Look for whoever may portray them. Leaving the
  party is on the Edit page, under the form, where nobody taps it mid-play; the GM's EXP and ABP
  grant is at the table, in GM tools' More, with a picker for who.
- **Maps are Prep's.** The maps page is reached from Prep (a button in its header and its nav), not
  from the top bar, which keeps to the places everyone goes: the campaign, the Table, My sheet,
  Prep, Legends. The map editor only builds: its side panel says where the party is and calls a
  waiting encounter, and travel is the table's (the Travel control, the map on the stage).
- **Setting up is the lobby's, playing is the table's.** Playing around one screen (the shared
  screen, the QR code and the controller link) is set up on the campaign page beside the invite,
  before play. The music is on the stage: one small select in the frame's top-left corner,
  just under where the party is, the GM's, since what the table hears belongs with what it sees. GM
  tools' More is grants only.
- **"Fast animations"**, not "Fast": the toggle says what it speeds up. It's a setting for this
  device, so it sits in the account menu beside Sound on every page, and a battle already
  playing hears the change. **The timing meter** is the same kind of thing, so its switch sits
  beside it, not under the commands.
- **The command panel's footer is gone.** Auto is the last row of the command menu, its state
  ("on", yellow) in the cost column and what it does in the help line; while a chosen command
  waits on the round, one short link turns it on or off. The keyboard legend shows only once a
  key has been used, and never on a phone. The panel's head is your name and the clock: your HP
  and MP are on the roster above it, and in the party strip on a phone once someone is hurt.
- **The log's battle section takes only the room it needs**, and section headings carry their own
  top gap, so nothing scrolled under them shows through.

### Only the battle

What's on screen in a fight is what you can do in it now (see "What you can do now").

- **The ticker on a phone is one line**: the last thing that happened. The log has the rest.
- **The party strip comes in with the first hit.** While everyone is at full HP it says nothing,
  so it stays hidden; once someone is hurt or KO'd it shows everyone.
- **The GM's panel keeps the round in sight**: who it waits on, rulings, both sides' tables, Run
  the round now and End the battle. Someone joins, Override and Pacing go behind one "GM controls"
  fold, opened when wanted.

### Defeat

When the whole party is down, the table decides what the story does with it: "Everyone is KO'd.
What happens now?" goes up as a choice like any other, with three ways on: retreat to the
nearest town by road (rested, with half the party's money gone, as in Dragon Quest), everyone
gets up where they fell with 1 HP, or game over. Players pick; the GM settles it, and the
battle's results say what was decided. A lost battle asks by itself; if the party fell some
other way, the GM puts it to the table.

### Players steer

The table's actions fit the moment the GM has called, and no others. The Now line has the
controls: **Talk** (the floor: the dialogue, nothing to pick), **Travel**, **Things to do
here**, **Scene**, **Check** and **Battle**; the one called is red and pressed, and one with
nothing behind it is greyed. Scene and Check are the GM's alone: the scene list or the check form comes to the
table under the stage, where the ways would be, and players see nothing until a scene plays or
a roll lands. Talking,
neither the GM nor the players get a menu of ways. Calling Travel puts "Where next?" below for
everyone: the open paths from where the party stands, a dungeon's door, or, inside, the ways on
from the room they're in (a room the players haven't seen is only "An unexplored way"). Calling
Things to do here puts the day's pastimes below instead, under "Day in Tule". The ways, like
the vote's options, are rows of a table, the whole row the control (`pick_table_controller`). A
player's row suggests it: the question goes to a vote with their pick in it; the GM settling the
vote takes the party there. The GM can also just go, from the same panel; to go or ask further
than a road from here, the GM presses a place on the map (Go, or Ask the table), or the map's
"Ask the table: anywhere on" button; the card stays open through the table's live refreshes
(the sheet is replaced with the panels, and the card comes back where it was). A battle, an encounter,
a scene or an open choice still comes first, whatever is called; the call stays until the GM
changes it, so a dungeon is walked room by room without re-pressing Travel. Settling the vote takes the party there. The
GM can also just go, from the same panel, and calls a waiting encounter there too, so a session
can run from the table without the map page.
In any vote, the option your own character picked stays filled red with "✓ Your pick" beside it,
so you can see your vote at a glance among everyone's names.

Staying is a way on as well. A place can list things to do there (`Pastime`): class, a shift, a
visit, a night in the other world. Each says when it can be done, how long it takes, what it
costs and what it does ("Work a shift (day, 2, money 40)"). The place's own head the list, under
"Day in Tule": "Attend class (until dusk)". They go to the same vote, and settling one pays, says
its line, makes its outcome happen and lets the time go by. This is the day schedule of a
calendar game: each part of the day is spent on something, and the countdowns on the date card
say what it costs.

A town's inn, temple and guild are things to do too, after the roads: "Rooms at the Gull (50
gil, overnight)", "A raising at the Chapel (100 gil)" when someone is KO'd, "Rumours at the
Guild (30 gil)". Where there's no inn, "Make camp (overnight)" takes its place. They have one
home: the table, under Things to do here, where the vote is. On the town page each service's
building says what it does and what it costs, and that it's done at the table; only the shop is
used on the page, because buying is the bag's business, not a way the day is spent. The party's
purse pays for everyone at once, not one character at a time.

### Someone awakens

The GM can have one character awaken to an archetype at the table ("Awaken someone": who, to
what, and what they hear). The archetype opens for the party if it wasn't open, they take it up
at once, and the table stops for it. Their face comes up on a white card with a yellow shadow,
and after a beat the card turns over. On the black back are whose it is ("Rook awakens"), what
they heard in yellow italic, the archetype's name in display type, and its description. The
card holds for about ten seconds, long enough to read it out, or until a click. A low drone and
a heartbeat play, then a chord that opens upward, and the scene's music holds still while the
card is up. The GM who pressed the button sees it too, on the table page they come back to.

### One More

A world can turn on One More (its Battle rules). A blow that finds a weakness, or lands a
critical hit, knocks its target down: "DOWN!" pops over them on black and yellow, and they lose
their next turn. Whoever struck goes again at once with the same move, under a slanted red "ONE
MORE!" across the stage, with a flash and a stab of brass. The other go finds its own mark: if
it was at one enemy, it goes for whoever is still standing and weakest to it, so a party can
knock a whole line down. On a phone the banner runs the full width above the pinned menu. It
happens once a turn, it works for enemies too, and someone already down isn't knocked down twice.
Commands are chosen for the whole round at its start, so the extra go repeats the move rather
than asking for a new one, as haste's second go does.

When the party has every enemy down, everyone who can act piles in: an **All-Out Attack**. A
black slab crosses the whole stage with "ALL-OUT ATTACK!" in red, the party bounces in turn over
a drum roll and a crash, and each of them lands an Attack on every enemy. Then the enemies
scramble back to their feet. It happens at most once a round.

### Daily life pays off

Time spent on things to do pays off through the party's archetypes, at the next rest. Each
archetype says how: money for the party, EXP or ABP for them (so much a part of the day), or a
rumour. Under the things to do, "At the next rest" says what each character's archetype will
make of it, and how many parts of the day have been spent so far. When the party sleeps, the
table hears each one in the archetype's own words ("Nim comes back with 80 gil and no
explanation"). Someone KO'd earns nothing.

### A place by night

A mode can come on by itself when the calendar says: the station after the last train, the
market when the shutters come down, the town snowbound in winter, the square on market day. It
turns on then and off otherwise. Words of one kind are any of them (dusk or night); words of
different kinds are all at once (winter nights). Modes layer: a place is in the one set off at
the table and every one the calendar has brought on, so the city can burn by night. Each one on
gets its own box on the place's page, and the map names them all ("Burning · By night"). A mode
can shut the place's usual things to do and bring its own, so the flooded station has no kiosk
shift but does have "Wade the platforms". Only the party, where it is, hears a mode come on,
and arriving somewhere says what the modes it's in say. Any place on the map has modes, a landmark
or the wilds as much as a town: the GM prepares a town's on its page and anywhere else's in the
map's panel. In the Atlas, a place's "What it's like by night" line becomes a "By night" mode in
every new campaign, in the setting's night.

### The setting's calendar

Each world sets its own calendar, and each part of it is made of the one before. Parts of the
day make a day, and some of them are its night; days make a week (the weekdays) and a month;
months, each with its own length and season, make a year; years make an era, written with #
for the year in it ("Heisei #", "# AC"). The world also sets the date the story starts on. A
school year runs Morning, After school, Evening, Late night, from Tuesday 7 April, Heisei 21.
A world with none of it has dawn, day, dusk and night, and counts days.

The date card says the date in display type, then the season and year in grey, then the part
of the day in its own box. The box wears the light, not the name: the first part of the day is
yellow, the night is blue-black, the part just before night is red, and the rest are white. A
rest sleeps until the first part of the day. Things to do and modes are kept to times with the
calendar's own words, and so are clocks: a clock can tick each new day, but only on market day, or each rest, but only in winter.

### A deadline passes

When a clock the table can see fills, the table stops for it. A red card comes up over
everything, the recap included. The date sits on a black band, the clock's line is set in
display type, and a bell tolls three times. If the clock sets a place into a new state, the
card names it ("Tule: Burning"). A click or a few seconds dismisses it. Every card that stops the table (this one, an awakening)
is played by one controller: a card is a dialog that says which cue brings it up, how long it
holds, how its parts come in and whether it turns over. The day before, the
countdown on the date card turns into a red band ("TOMORROW The spring tide comes in"), and on
a phone that band stays pinned along the bottom of the screen.

### A boss, and a place cleared

Walking in on a dungeon's boss, the GM gets a few lines for its entrance, written from the
place's past, to say as they are, rewrite or clear; the battle waits for them. Beating the boss
is cheered at the table with a fanfare of its own, and the clocks that place was behind stop.

### Talk that leads somewhere

A place the party doesn't know yet can come with its lead: what people say about it. The talk
starts in the nearest town by road, and hearing it (arriving there, or buying it at a guild)
puts the place on the map. Townsfolk hooks name real places too: the nearest town or dungeon
by road.

### Phones

Phones are where most players are, so every page is checked at 390×844, 360×640 and on its side.

- **The top bar is one line**: the name, a Menu button, and the log's tab. The links open from
  Menu at 44px, with Sign out set apart at the end, where a guest won't tap it by mistake. The
  log's tab scrolls away with the bar instead of floating over what you're reading.
- **The table is three views, on a phone and on a tablet alike** (up to 1099px). Its three
  columns (you and the party; the stage and what you can do; the log) are too much for one
  screen stacked, so a strip in the top bar, between the brand and Menu, picks one: "You &
  party", "Stage", "Log", the one shown on paper in the bar's ink, the Stage first. On a tablet
  the bar folds its links behind Menu as a phone's does, to make room. The log's tab goes away
  on this page: the log is the third view, in the page, and the count of lines you haven't seen
  sits on its name in the strip. The view you were on is kept for the session.
- **Menu is the trigram ☰**, before the wordmark, turned a quarter while open, wherever the links
  fold (a phone, and the table up to a tablet's width); the table's three views sit at the bar's
  right end, plain names with no border, the one shown on paper.
- **A sheet is its player's and the GM's.** Nobody else opens a character's sheet (gear, items,
  archetypes and all): on the campaign page their card is a card, not a link, and the table's party
  panel names them. The GM opens every sheet.
- **Items are each adventurer's own, and the party has a chest.** What a character carries is in
  their own bag: it goes into battle with them, is what they wear from, use outside battle and sell
  at a shop; what they buy goes into their bag. The chest is the party's: what's found, dropped or
  stolen goes into it, and anyone takes from it or puts into it from
  their sheet's Gear tab, which shows their bag beside the chest. Leaving the party leaves gear and
  bag in the chest. A wish or a "give" takes from the chest first, then from whoever carries it.
  In battle everything the party has, bags and chest, is one flat count for the Item command (the
  engine shares the party's items); used ones come out of their own bags first, then the chest.
- **A scene's music step can name a track**: the Music book's tracks called by name, a YouTube or
  Spotify link among them, sit in the step's select after the kinds of scene, as on the stage's switch.
- **The log reads newest first.** A new line lands on top, and opening the log shows the top, so
  the latest is always at hand without scrolling; the battle's own section still grows downward
  as a fight plays. A search box sits in the log's sticky head: typing narrows the lines to the
  ones with those words, new lines included, and clearing it shows all.
- **In battle, the commands are pinned to the bottom** while the fight plays above them. The
  pinned panel carries a strip of everyone's HP and, above it, the last lines of what just
  happened, so nobody has to open the log mid-fight. The page title steps aside and enemies size
  to the room that's left. Results and "Try something" let go of the bottom edge, with the way on
  first. Commands are 48px, everything else tappable at least 44px.
- **On its side**, a phone shows the field and the commands next to each other.
- **At the table**, the composer sits under "Where next?", where the story is, not below the map.
  "Where next?" is one column. Notices ("Bought.") float over the page as toasts wherever you've
  scrolled to.
- **Long pages** (the character sheet, How to play) have shortcuts to their sections; tables stack
  as cards where their columns won't fit. Glossary definitions open as a sheet along the bottom.
- **The map** grows its place names on a phone, and a player can tap a place to look at it.

## Divergences

Record each place where the game needed more than the Swiss defaults: what changed and why.

- **The play layer** (above) adds a game-menu cursor, a help line, highlighted targets and key
  bindings. It changes behaviour rather than style, so it is less a break from Swiss than an
  addition to it.
- **No measure on a desktop.** The page's 1200px measure goes at 1100px and up: a game is played
  on the whole screen, with the pinned columns on its far edges and the Stage between them. The
  books keep their own measures (prose at 64ch, forms at 1000px).
- **Low HP turns amber.** At a quarter of max HP or less, the HP number and bar go amber
  (`--caution`), in the roster, the player's own panel, the GM's unit table and the table's party
  panel (still there, not blinking: nothing is urgent outside a fight). A bold black
  number read too slowly mid-fight. Amber stays clear of the interaction red.
- **Statuses are colour-coded,** as in the games: poison green, sleep blue, paralyze yellow,
  silence purple, blind charcoal, haste teal and slow brown. They are solid badges, and a newly
  applied status pops up in its own colour. A row of identical black outlines couldn't be read
  at a glance. Red is still kept for interaction.
- **Enemy targets show what the Bestiary knows.** The help line gives the enemy's level and its
  affinities (weak to, resists, immune to, absorbs, including status immunities), but never its
  HP. Players can already read these in the Bestiary, so the battle doesn't hide them.
- **The table leads with the dialogue box** and mirrors the last few lines under it (above). The
  Swiss start put the map first and everything said in a closed drawer; players missed the story.
- **Struck through, not faded.** A fallen unit's name is struck through in full-strength ink
  (white on the enemies' side). Fading it to grey, as Swiss would, took it below a readable
  contrast on the battlefield's colours. The targeted enemy's name is ink on yellow for the same
  reason.
- **The GM's log can be a column.** Swiss would keep the drawer closed and the page whole. The GM
  follows whispers, rolls and the story at once, and at the table the log is their record, so on a
  wide screen it's pinned open beside the page, which gets narrower for it.
- **Grey controls, red moves.** The starting point made every interactive thing red, so
  navigation and admin drowned out the game. Controls are now grey, and red is kept for game
  moves (`.play`).

- **The date is one line on the stage.** **The day clock** (a dial cut into a slice for each part of
  the setting's day, each in its light's colour, turned so the part it is now points right) and
  the part of the day as a label in that part's colour (dawn yellow, day white, dusk red, night
  blue) are one shape with one outline: the label's left edge is the chord where the clock's ring
  stops and its border carries the line on, and the slice pointing at it is its colour, so the
  slice runs into the label with no line between. There is no pointer: the label is the pointer.
  Then the day in the setting's calendar at the same size, black on white, carrying on the label's
  border and cut off with a slant (the `/` of the type tags). When time passes the dial turns forward (never back: into
  the next day it keeps going round), so the table sees the day move. Under the line, the days
  left on each public clock that only a new day ticks, said as a sentence ("5 days until The
  spring tide comes in"; on the last day, "Tomorrow it happens: …"). Where the party is (the
  place's name, a link to it, with the room inside a dungeon: "The Drowned Line · Entrance") is a
  tag in the frame's other top corner. The party plans around the calendar, but the line shouldn't
  take the eye off the stage, so on the stage it has no plate of its own.
- **Name tags in the speaker's colour.** The dialogue box's name tag wears the speaker's plate
  colour instead of a fixed yellow. The narrator has no portrait: narration is a voice, and its
  words take the whole box. On a phone a speaker's portrait is 64px beside their words, where it
  used to be a plate half the screen high.
- **On the stage the dialogue box is the speaker's height.** One compact box along the frame's
  bottom, the speaker's portrait inside it flush to its left edge, and the box exactly as tall as
  the portrait. The name tag is a tab on its top edge. A line that doesn't fit isn't scrolled: it is
  split into pages that each fit, typed out one after another (press for the next, or they move on
  by themselves). Narration, with no face to match, is as tall as its words, up to the same height.
  A small × puts the box away: what it still had to say is in the log, and the next line brings it
  back. The same box plays on a battle's stage.
- **Story time in the log.** Log lines show the part of the day they were said in ("Dusk"), and
  the recap is dated by the setting's calendar. The wall-clock time is only on hover, because
  "00:17" in a fantasy log breaks the fiction.
- **Red for a deadline.** A deadline passing is a red card, and its last day is a red band. That's
  the one place red means something other than a move: the game stopping you. A grey or black
  card read as one more notice, and the Persona table missed the biggest beat of its campaign.
