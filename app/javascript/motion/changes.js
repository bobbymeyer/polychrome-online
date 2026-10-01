// Motion with meaning (docs/DESIGN.md, "Motion with meaning"): when a live
// panel is replaced or morphed, whatever changed in it says so, the same
// way everywhere. A view marks what matters with data-change:
//
//   number  a value that counts to its new figure (HP, cones, a clock's count)
//   bar     a fill whose width eases, leaving a ghost of where it was
//   text    words that get a wash when they're different
//   list    children that slide in when they're new (keyed by data-change-key)
//   clock   a dial whose newly filled boxes pop, and shakes once when full
//
// Elements are matched across a refresh by data-change-key, id, or their
// place among the marks. Reduced motion keeps the facts (data-changed-from,
// the classes) and skips the movement. Also used by the battle board for
// its HP bars (battle/board.js).

const MARK = "[data-change]"
const COUNT_MS = 500
const SETTLE_MS = 600
const ENTER_MS = 300

const reduced = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches
const kinds = (el) => el.dataset.change.split(/\s+/)
const keyOf = (el, index) => el.dataset.changeKey || el.id || `${el.dataset.change}:${index}`
const childKey = (child, index) => child.dataset.changeKey || child.id || child.textContent.trim() || String(index)
const number = (text) => Number(String(text).replace(/[^\d.-]/g, ""))

// What a root's marks say now, before it's refreshed.
export function snapshot(root) {
  const before = {}
  root.querySelectorAll(MARK).forEach((el, i) => {
    const entry = {}
    kinds(el).forEach((kind) => {
      // Mid-count, the figure it's counting to, not the one passing through.
      if (kind === "number") Object.assign(entry, { number: number(el.dataset.changeValue ?? el.textContent), changedFrom: el.dataset.changedFrom })
      else if (kind === "bar") entry.bar = parseFloat(el.style.width)
      else if (kind === "text") entry.text = el.textContent.trim()
      else if (kind === "list") entry.list = new Set(Array.from(el.children, childKey))
      else if (kind === "clock") Object.assign(entry, { clock: el.querySelectorAll(".is-filled").length, popped: Array.from(el.querySelectorAll("i.is-new"), (box) => Array.prototype.indexOf.call(box.parentElement.children, box)) })
    })
    before[keyOf(el, i)] = entry
  })
  return before
}

// After the refresh: each mark against what it said before.
export function settle(root, before) {
  root.querySelectorAll(MARK).forEach((el, i) => {
    const was = before[keyOf(el, i)]
    if (!was) return enter(el)

    kinds(el).forEach((kind) => {
      if (kind === "number" && was.number !== undefined) countTo(el, was.number, was)
      else if (kind === "bar" && was.bar !== undefined) animateBar(el, was.bar)
      else if (kind === "text" && was.text !== undefined && was.text !== el.textContent.trim()) flash(el, "is-changed")
      else if (kind === "list" && was.list) Array.from(el.children).forEach((child, j) => { if (!was.list.has(childKey(child, j))) enter(child) })
      else if (kind === "clock" && was.clock !== undefined) fillClock(el, was.clock, was.popped)
    })
  })
}

// A number counts from where it was to where it is, and keeps where it
// came from (data-changed-from) for anyone who asks.
export function countTo(el, from, { changedFrom } = {}) {
  const to = number(el.textContent)
  // The same figure again (a panel refreshed for another reason): the last change stays on record.
  if (from === to && changedFrom) el.dataset.changedFrom = changedFrom
  if (Number.isNaN(from) || Number.isNaN(to) || from === to) return

  const text = el.textContent
  el.dataset.changedFrom = from
  el.dataset.changeValue = to
  flash(el, to > from ? "is-up" : "is-down")
  if (reduced()) return

  const grouped = text.includes(",")
  const start = performance.now()
  const step = (now) => {
    const t = Math.min(1, (now - start) / COUNT_MS)
    const eased = 1 - (1 - t) * (1 - t)
    const value = Math.round(from + (to - from) * eased)
    el.textContent = t < 1 ? (grouped ? value.toLocaleString("en") : String(value)) : text
    if (t < 1) requestAnimationFrame(step)
  }
  requestAnimationFrame(step)
}

// A bar eases from its old width to its new one; a ghost holds the old
// length a beat longer, so a loss (or a gain) can be read as a length.
export function animateBar(fill, from) {
  const to = parseFloat(fill.style.width)
  if (Number.isNaN(from) || Number.isNaN(to) || from === to) return
  const bar = fill.parentElement
  if (!bar || reduced()) return

  bar.querySelectorAll(".bar__ghost").forEach((ghost) => ghost.remove())
  const ghost = document.createElement("i")
  ghost.className = "bar__ghost"
  ghost.style.width = `${Math.max(from, to)}%`
  bar.append(ghost)

  fill.style.transition = "none"
  fill.style.width = `${from}%`
  void fill.offsetWidth // settle the old width before easing to the new one
  fill.style.transition = ""
  fill.style.width = `${to}%`
  setTimeout(() => {
    ghost.style.width = `${to}%`
    setTimeout(() => ghost.remove(), SETTLE_MS)
  }, SETTLE_MS)
}

// A dial's newly filled boxes pop in turn; the last one shakes the dial.
function fillClock(dial, from, popped = []) {
  const boxes = dial.querySelectorAll("i")
  const to = dial.querySelectorAll(".is-filled").length
  if (to < from) return flash(dial, "is-changed")
  // The same count again (refreshed for another reason): the boxes that popped stay marked, without popping twice.
  if (to === from) return popped.forEach((i) => { boxes[i]?.classList.add("is-new"); boxes[i]?.style.setProperty("animation", "none") })
  for (let i = from; i < to; i++) {
    boxes[i].style.animationDelay = `${(i - from) * 80}ms`
    boxes[i].classList.add("is-new")
  }
  if (to === boxes.length && from < to) flash(dial, "is-just-full", 800)
}

function enter(el) {
  el.classList.add("is-new")
  setTimeout(() => el.classList.remove("is-new"), ENTER_MS * 2)
}

// A class put on for a moment, restarted if it's already on.
function flash(el, klass, ms = SETTLE_MS) {
  el.classList.remove(klass)
  void el.offsetWidth
  el.classList.add(klass)
  setTimeout(() => el.classList.remove(klass), ms)
}

// --- Turbo: panels replaced by a stream, pages refreshed by a morph --------

document.addEventListener("turbo:before-stream-render", (event) => {
  const stream = event.target
  if (!["replace", "update"].includes(stream.action)) return

  const befores = stream.targetElements.filter((el) => el.id).map((el) => [el.id, snapshot(el)])
  if (befores.length === 0) return

  const render = event.detail.render
  event.detail.render = async (streamElement) => {
    await render(streamElement)
    befores.forEach(([id, before]) => {
      const el = document.getElementById(id)
      if (el) settle(el, before)
    })
  }
})

// A morph says each element before and after. The outermost one carries
// the snapshot, so nothing inside it is counted twice.
const pending = new Map()

document.addEventListener("turbo:before-morph-element", (event) => {
  const el = event.target
  for (const held of pending.keys()) if (held.contains(el)) return
  if (el.querySelector?.(MARK) || el.matches?.(MARK)) pending.set(el, snapshot(el))
})

document.addEventListener("turbo:morph-element", (event) => {
  const before = pending.get(event.target)
  if (!before) return

  pending.delete(event.target)
  settle(event.target, before)
})
