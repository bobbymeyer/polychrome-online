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
- **The masthead** is a black band, full bleed, with the palette as a stripe under it.
- **Ground.** A halftone falls from the top right of every page and fills the enemies' side of the
  battlefield; the party's side is a slanted grey wash.
- **Shadows.** Only hard ones, offset, never blurred: a focused field, the dialogue box.
- **Menus.** Game menus (`.play`) are white slabs underlined in red. They slide in one after
  another when a panel opens. The cursor is a red slab thrown 8px forward with a black edge.
  Grey menus behave the same in grey and black.
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
  holds the table's log; in battle, the battle's log with the table's beneath it.
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
  "Goblin Chief falls!".
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
- **A check** takes the middle of every screen: the character, the stat and the odds, then a
  heavy number spinning to a stop and the verdict stamped in green or red, with a jingle.
  Several go one after another.
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

Music is the world's own: a track for each kind of scene (field, town, dungeon, battle,
boss), uploaded on the world's edit page. Each page plays its scene's track, crossfading as
you move, and a scene without a track is quiet. At the table the GM can switch everyone to
another scene's track, or to silence; battles keep their own. A boss's entrance stops the
music for its moment, then the boss track starts.

Nothing sounds until the viewer has clicked or pressed a key (browsers insist), and "Sound
on/off" in the top bar mutes this device.

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
creature outlined in white so any colour reads), the party on a slanted slab of Sun Yellow.
The art is the show there: enemies stand 176px tall and the party 96px (120 and 72 on a phone),
twice the size the Swiss grid would give them.

The masthead is black, with the whole palette as a stripe under it. Uploaded images are content
and keep their own colours.

## Geometry

Simple shapes carry meaning, and each one is explained in a legend next to the map that uses it.

| Thing | Shape |
|---|---|
| Enemy | Square with its initial and a cut corner, in its own colour, outlined in white |
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

## Play

The Swiss surface still has to play like a JRPG. Anything a player does in a turn works from the
keyboard, a mouse or a finger.

- **Command menus** (`menu` Stimulus controller) have a cursor. In a game menu the cursor is
  the red fill; in any other menu it is grey.
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
- **Touch:** menu items are at least 48px tall and buttons at least 44px on coarse pointers. The
  keyboard legend is hidden on devices without hover.

## Divergences

Record each place where the game needed more than the Swiss defaults: what changed and why.

- **The play layer** (above) adds a game-menu cursor, a help line, highlighted targets and key
  bindings. It changes behaviour rather than style, so it is less a break from Swiss than an
  addition to it.
- **Low HP turns amber.** At a quarter of max HP or less, the HP number and bar go amber
  (`--caution`), in the roster, the player's own panel and the GM's unit table. A bold black
  number read too slowly mid-fight. Amber stays clear of the interaction red.
- **Statuses are colour-coded,** as in the games: poison green, sleep blue, paralyze yellow,
  silence purple, blind charcoal, haste teal and slow brown. They are solid badges, and a newly
  applied status pops up in its own colour. A row of identical black outlines couldn't be read
  at a glance. Red is still kept for interaction.
- **Enemy targets show what the Bestiary knows.** The help line gives the enemy's level and its
  affinities (weak to, resists, immune to, absorbs, including status immunities), but never its
  HP. Players can already read these in the Bestiary, so the battle doesn't hide them.
- **Grey controls, red moves.** The starting point made every interactive thing red, so
  navigation and admin drowned out the game. Controls are now grey, and red is kept for game
  moves (`.play`).

