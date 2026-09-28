# CLAUDE.md

- `docs/HANDOFF.md` is the design contract. Read it before writing code. Where a shortcut conflicts with it, the document wins.
- `docs/DESIGN.md` is the visual starting point: Swiss rather than SNES, with black grotesk type on white, geometry for state, grey controls and red for game moves. Diverge where the game needs it, and record each divergence in that document.
- `lib/battle` and `lib/stats` are pure functions over plain data: no ActiveRecord, no I/O, no global state. Randomness only comes from the RNG state stored in the battle state.
- Run the tests with `bin/rspec`. A change to resolver behaviour needs the property specs (`spec/battle/properties_spec.rb`) to stay green.
- `spec/system` drives the live pages (streams, refreshes, the battle player) in headless Chrome, several browsers at once. Set `CHROME_BIN` to use a particular Chrome or Chromium; a matching driver is fetched for it. Wait for a page's streams (`wait_for_streams`) before changing what it should hear about.
- Omakase Rails until it is painful not to be (HANDOFF §10). Use SQLite and the Rails 8 defaults, and add no gems or infrastructure until a concrete problem calls for it.
