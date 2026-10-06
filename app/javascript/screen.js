// The screen this is playing on, asked the same way everywhere. The widths
// are the stylesheet's folds (stage.css): keep them in step.

const query = (q) => window.matchMedia(q).matches

// The viewer asked for less movement: motion stops, and anything timed by it
// goes straight to its end.
export const reducedMotion = () => query("(prefers-reduced-motion: reduce)")

// A phone or a tablet: the table's three columns are three views, the log is a view, not a drawer.
export const narrow = () => query("(max-width: 1099px)")

// A phone: one column, and the results have to be brought into view.
export const phone = () => query("(max-width: 640px)")

// A wide screen (1440, less its scrollbar): the GM's log starts pinned.
export const wide = () => atLeast(1400)

export const atLeast = (px) => query(`(min-width: ${px}px)`)
