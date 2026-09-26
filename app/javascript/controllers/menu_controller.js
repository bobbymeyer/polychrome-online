import { Controller } from "@hotwired/stimulus"

// A command menu played like a game (docs/DESIGN.md, "Play"): a cursor that
// follows the arrow keys and the mouse, Enter/Space/Z to choose, Esc/X/
// Backspace to go back, 1–9 to pick directly. A help line says what the
// cursor is on. Target options light up their unit on the battlefield, and
// the units themselves can be clicked.
//
// Only a `primary` menu listens to the whole window; others answer keys only
// while focus is inside them.

let remembered = null // the label the cursor was on, kept across panel reloads

const TYPING = "input, textarea, select, [contenteditable]"

export default class extends Controller {
  static targets = ["help"]
  static values = { primary: Boolean, autofocus: Boolean, you: String }

  connect() {
    this.onKey = this.key.bind(this)
    ;(this.primaryValue ? window : this.element).addEventListener("keydown", this.onKey)
    this.onOver = (e) => { const item = e.target.closest(".menu__item"); if (item) this.moveTo(item, { focus: false }) }
    this.element.addEventListener("mouseover", this.onOver)
    this.onFocus = (e) => { const item = e.target.closest(".menu__item"); if (item) this.moveTo(item, { focus: false }) }
    this.element.addEventListener("focusin", this.onFocus)

    this.markYou(true)
    this.bindTargets()

    const items = this.items
    if (!items.length) return
    const start = items.find((i) => this.label(i) === remembered) || items.find((i) => !this.disabled(i)) || items[0]
    const take = this.autofocusValue && this.mayTakeFocus()
    this.moveTo(start, { focus: take })
    if (take) this.bringIntoView()
  }

  // On a short screen your turn can start below the fold: scroll just enough to show the menu.
  bringIntoView() {
    const box = this.element.querySelector(".menu")?.getBoundingClientRect()
    if (!box || (box.top >= 0 && box.bottom <= window.innerHeight)) return
    const smooth = !window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.element.scrollIntoView({ block: "nearest", behavior: smooth ? "smooth" : "auto" })
  }

  disconnect() {
    ;(this.primaryValue ? window : this.element).removeEventListener("keydown", this.onKey)
    this.element.removeEventListener("mouseover", this.onOver)
    this.element.removeEventListener("focusin", this.onFocus)
    this.highlight(null)
    this.unbindTargets()
    this.markYou(false)
  }

  get items() {
    return [...this.element.querySelectorAll(".menu__item")]
  }

  get cursor() {
    return this.element.querySelector(".menu__item.is-cursor")
  }

  key(event) {
    if (event.defaultPrevented || event.altKey || event.ctrlKey || event.metaKey) return
    if (event.target.closest?.(TYPING)) return
    if (this.element.closest(".is-resolving")) return // a beat is playing; the battle player has the keys
    if (this.primaryValue && !this.element.contains(event.target) && event.target !== document.body) {
      // Focus is on something else on the page (a link, a button): leave it alone.
      return
    }

    const items = this.items
    const cursor = this.cursor
    switch (event.key) {
      case "ArrowDown": case "ArrowUp": case "ArrowLeft": case "ArrowRight": {
        if (!items.length) return
        event.preventDefault()
        this.moveTo(cursor ? this.neighbour(cursor, event.key, items) : items[0])
        return
      }
      case "Enter": case " ": case "z": case "Z": {
        if (!cursor) return
        // A focused button already fires on Enter/Space; only step in when it isn't focused.
        if (document.activeElement === cursor && event.key !== "z" && event.key !== "Z") return
        event.preventDefault()
        this.choose(cursor)
        return
      }
      case "Escape": case "Backspace": case "x": case "X": {
        const back = this.element.querySelector("[data-menu-back]")
        if (!back) return
        event.preventDefault()
        back.click()
        return
      }
      default:
        if (/^[1-9]$/.test(event.key) && items[Number(event.key) - 1]) {
          event.preventDefault()
          const item = items[Number(event.key) - 1]
          this.moveTo(item)
          this.choose(item)
        }
    }
  }

  choose(item) {
    if (this.disabled(item)) return this.flashHelp()
    remembered = this.label(item)
    item.click()
  }

  moveTo(item, { focus = true } = {}) {
    this.items.forEach((i) => i.classList.toggle("is-cursor", i === item))
    if (focus && !this.disabled(item)) item.focus({ preventScroll: true })
    else if (focus) item.focus?.({ preventScroll: true })
    remembered = this.label(item)
    if (this.hasHelpTarget) this.helpTarget.textContent = item.dataset.help || ""
    this.highlight(item.dataset.unitId || null)
  }

  // Up/down go to the nearest item in the row above/below; left/right step
  // through in reading order. All four wrap, like a game menu.
  neighbour(from, key, items) {
    const i = items.indexOf(from)
    if (key === "ArrowRight") return items[(i + 1) % items.length]
    if (key === "ArrowLeft") return items[(i - 1 + items.length) % items.length]

    const box = (el) => el.getBoundingClientRect()
    const here = box(from)
    const x = here.left + here.width / 2
    const down = key === "ArrowDown"
    const rows = [...new Set(items.map((el) => Math.round(box(el).top)))].sort((a, b) => a - b)
    const row = rows.indexOf(Math.round(here.top))
    const next = rows[(row + (down ? 1 : -1) + rows.length) % rows.length]
    const inRow = items.filter((el) => Math.round(box(el).top) === next)
    return inRow.reduce((best, el) => {
      const d = Math.abs(box(el).left + box(el).width / 2 - x)
      return d < best.d ? { el, d } : best
    }, { el: inRow[0], d: Infinity }).el
  }

  disabled(item) {
    return item.disabled || item.getAttribute("aria-disabled") === "true"
  }

  label(item) {
    return item.dataset.menuKey || item.textContent.trim()
  }

  mayTakeFocus() {
    const active = document.activeElement
    return !active || active === document.body || this.element.contains(active) || active.closest("turbo-frame")
  }

  flashHelp() {
    if (!this.hasHelpTarget) return
    this.helpTarget.classList.remove("is-flashing")
    void this.helpTarget.offsetWidth
    this.helpTarget.classList.add("is-flashing")
  }

  // --- the battlefield ------------------------------------------------------

  board() {
    return document.querySelector(".board")
  }

  unitEls(id) {
    return this.board()?.querySelectorAll(`[data-unit="${CSS.escape(id)}"], [data-roster="${CSS.escape(id)}"]`) || []
  }

  highlight(id) {
    this.board()?.querySelectorAll(".is-targeted").forEach((el) => el.classList.remove("is-targeted"))
    if (id) this.unitEls(id).forEach((el) => el.classList.add("is-targeted"))
  }

  markYou(on) {
    if (!this.youValue) return
    this.unitEls(this.youValue).forEach((el) => el.classList.toggle("is-you", on))
  }

  // While choosing a target, each targetable unit on the field is a button too.
  bindTargets() {
    this.bound = []
    this.items.filter((item) => item.dataset.unitId).forEach((item) => {
      this.unitEls(item.dataset.unitId).forEach((el) => {
        const click = () => this.choose(item)
        const over = () => this.moveTo(item, { focus: false })
        el.classList.add("is-targetable")
        el.addEventListener("click", click)
        el.addEventListener("mouseenter", over)
        this.bound.push([el, click, over])
      })
    })
  }

  unbindTargets() {
    this.bound?.forEach(([el, click, over]) => {
      el.classList.remove("is-targetable")
      el.removeEventListener("click", click)
      el.removeEventListener("mouseenter", over)
    })
    this.bound = []
  }
}
