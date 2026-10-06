// The stage (docs/DESIGN.md, "The stage"): moments that take over every screen
// at the table. When a battle starts, everyone is pulled into it: slabs of the
// palette sweep across the screen, the page follows, and they sweep away on
// the other side. Where you came from is remembered, so the battle can send
// you back.
import { play, holdMusic } from "sound"
import { get, getJSON, set, remove } from "storage"
import { reducedMotion } from "screen"

const RETURN_KEY = "polychrome.returnTo"
const ARRIVE_KEY = "polychrome.arriving"
const SLABS = 7
const COVER_MS = 700
const DIALOGUE_WAIT_MS = 20000
// A scene's lines and its battle go out together, and can arrive in any
// order: give the lines a moment to land before asking if anyone's talking.
const SETTLE_MS = 600

// Where you came from is this tab's business (session: true), not the device's.
const TAB = { session: true }

export function toBattle(url, { boss = false } = {}) {
  const root = document.documentElement
  if (window.location.pathname === new URL(url, window.location.href).pathname || root.dataset.leaving) return
  // Nobody is pulled out of a fight they're still in (a split party); from
  // one that's over, the next one takes them.
  if (document.querySelector(".battle .board")?.dataset.status === "input") return

  root.dataset.leaving = "true"
  // From one battle's results into the next, the way back stays where the
  // first one was called from.
  if (!document.querySelector(".battle")) {
    set(RETURN_KEY, JSON.stringify({ url: window.location.href, title: document.title.replace(/ · Polychrome$/, "") }), TAB)
  }
  // Nobody is pulled away mid-sentence: a scene's lines finish first.
  setTimeout(() => whenDialogueIdle(() => {
    holdMusic()
    play(boss ? "boss" : "encounter")
    if (reducedMotion()) return window.Turbo.visit(url)

    wipe("in", boss)
    setTimeout(() => {
      set(ARRIVE_KEY, boss ? "boss" : "battle", TAB)
      window.Turbo.visit(url)
    }, COVER_MS)
  }), SETTLE_MS)
}

// Where the battle should send you back to, if you were pulled in.
export function takeReturn() {
  return getJSON(RETURN_KEY, null, TAB)
}

export function forgetReturn() {
  remove(RETURN_KEY, TAB)
}

function whenDialogueIdle(fn, waited = 0) {
  if (document.documentElement.dataset.dialogueBusy !== "true" || waited >= DIALOGUE_WAIT_MS) return fn()
  setTimeout(() => whenDialogueIdle(fn, waited + 250), 250)
}

function wipe(direction, boss) {
  const el = document.createElement("div")
  el.className = `stage-wipe stage-wipe--${direction}${boss ? " stage-wipe--boss" : ""}`
  el.setAttribute("aria-hidden", "true")
  for (let i = 0; i < SLABS; i++) {
    const slab = document.createElement("span")
    slab.style.setProperty("--i", i)
    el.append(slab)
  }
  document.body.append(el)
  return el
}

document.addEventListener("turbo:load", () => {
  delete document.documentElement.dataset.leaving
  const arriving = get(ARRIVE_KEY, TAB)
  remove(ARRIVE_KEY, TAB)
  if (!arriving || reducedMotion()) return

  const el = wipe("out", arriving === "boss")
  setTimeout(() => el.remove(), 1000)
})
