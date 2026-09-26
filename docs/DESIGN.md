# Design

The mechanics are JRPG. The presentation is not: it is set as if Josef Müller-Brockmann had been
asked to port the game to modern screens. Every page follows these rules. The stylesheet is
`app/assets/stylesheets/application.css`.

## Paper and type

- White paper with black type. There is no dark theme, and no shadows, gradients or rounded corners.
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

Colour means interaction, and only interaction. There is one colour: Swiss red `#d71920`.

- **Red:** links, buttons, menu and command options, form focus, disclosure triangles, map
  places and paths the GM can edit (on hover), and the dialogue's advance square.
- **State is never red.** HP, KO, the current room, whose turn it is and where the party stands
  are all shown with black geometry, weight, fill and outline.
- A selected option (the current pacing, say) is filled black. A pressed toggle (a pinned
  element) is filled red.
- Uploaded images are content and keep their own colours.

## Geometry

Simple shapes carry meaning, and each one is explained in a legend next to the map that uses it.

| Thing | Shape |
|---|---|
| Enemy | Black square with its initial |
| Party member | Black circle with their initial |
| Knocked out | The same shape, outline only |
| Ready (input in) | Small black square in the roster |
| Active unit | Heavy rule under its name |
| Town | Black square |
| Dungeon | Black triangle |
| Field | Black circle |
| Event | Black diamond |
| Hidden place (GM only) | Dashed outline |
| Party on a map | Black triangle pointing down at them |
| Open, dangerous and blocked paths | Solid line, dashed line, and grey dotted line with an × |
| Encounter, boss, treasure, event and fork rooms | Small square, large square, diamond, circle, and a branching line |
| Costly way in a dungeon | Dashed path with a black diamond at its middle |
| Current room | The room shown inverted (black) |
| Resolved room | Its marker shown in outline |

No emoji or pictographic glyphs. An arrow (→) is typography and may follow a link.

## Motion

The gestures in HANDOFF §3.2 stay. `tint` is an inversion pulse, because a hue shift is
invisible in black and white. Banners are giant black type, set flush left on the stage.
Captions are black bars with white type.
