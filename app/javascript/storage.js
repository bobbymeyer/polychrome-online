// What this browser remembers: settings for this device (localStorage) and
// things for this tab (sessionStorage, `session: true`). Storage can be
// missing or refused (a private window, a locked-down browser): every call
// here fails quietly, so a page without it still works, it just forgets.
//
// `get` answers null for a key never set and undefined when storage can't be
// read at all, for the few callers that treat the two differently.

function area(session) {
  return session ? window.sessionStorage : window.localStorage
}

export function get(key, { session = false } = {}) {
  try { return area(session).getItem(key) } catch { return undefined }
}

export function set(key, value, { session = false } = {}) {
  try { area(session).setItem(key, value) } catch { /* no storage: for this page only */ }
}

export function remove(key, { session = false } = {}) {
  try { area(session).removeItem(key) } catch { /* nothing kept, nothing to forget */ }
}

// A value kept as JSON; `fallback` when there's none, or it can't be read.
export function getJSON(key, fallback, { session = false } = {}) {
  try {
    const raw = area(session).getItem(key)
    return raw === null ? fallback : JSON.parse(raw)
  } catch { return fallback }
}

export function setJSON(key, value, { session = false } = {}) {
  set(key, JSON.stringify(value), { session })
}

// --- a list of things seen, capped ------------------------------------------
// A moment that plays once per viewer (a jingle, a boss's entrance, a card)
// keeps its id in a short list under listKey; the oldest fall off its end.

export function seen(listKey, id, { session = false } = {}) {
  return list(listKey, session).includes(id)
}

export function markSeen(listKey, id, { cap = 50, session = false } = {}) {
  const ids = list(listKey, session).filter((i) => i !== id)
  setJSON(listKey, [ ...ids, id ].slice(-cap), { session })
}

function list(key, session) {
  const ids = getJSON(key, [], { session })
  return Array.isArray(ids) ? ids : []
}

// --- a device setting: on or off --------------------------------------------
// Settings are written as "1"/"0" now; older ones were kept as "on"/"off"
// (the meter) or "true"/"false" (sound), and still read.

const ON = [ "1", "on", "true" ]
const OFF = [ "0", "off", "false" ]

export function setting(key, fallback = false) {
  const saved = get(key)
  if (ON.includes(saved)) return true
  if (OFF.includes(saved)) return false
  return fallback
}

export function setSetting(key, on) {
  set(key, on ? "1" : "0")
}
