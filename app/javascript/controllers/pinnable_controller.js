import { Controller } from "@hotwired/stimulus"

// A part of a player's screen that pins on a wide screen, the way the log
// does on the right: the left column (you), beside the scene, and the
// actions, along the bottom of it. Unpinned, it folds away (the left
// column to a tab on the edge, the actions to a bar) and opens when pressed.
// It stays as you left it, in this browser. Narrower than WIDE, it's
// simply part of the page.
const WIDE = 1100

export default class extends Controller {
  static targets = ["pin"]
  static values = { key: String }

  connect() {
    this.wide = window.matchMedia(`(min-width: ${WIDE}px)`)
    this.onWide = () => this.apply()
    this.wide.addEventListener("change", this.onWide)
    this.apply()
  }

  disconnect() {
    this.wide.removeEventListener("change", this.onWide)
  }

  togglePin() {
    try { localStorage.setItem(this.keyValue, this.pinned ? "0" : "1") } catch {}
    this.apply()
  }

  toggle() {
    this.element.classList.toggle("is-open")
  }

  get pinned() {
    try { return localStorage.getItem(this.keyValue) !== "0" } catch { return true }
  }

  apply() {
    const pinned = this.wide.matches && this.pinned
    this.element.classList.toggle("is-pinned", pinned)
    this.element.classList.remove("is-open")
    if (this.hasPinTarget) {
      this.pinTarget.setAttribute("aria-pressed", String(pinned))
      this.pinTarget.textContent = pinned ? "Unpin" : "Pin"
    }
  }
}
