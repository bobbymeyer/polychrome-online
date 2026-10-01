import { Controller } from "@hotwired/stimulus"

// The top bar: on a phone its links open from a Menu button; the account's
// menu (your name) closes on a click elsewhere or Esc. The page starts under
// the bar, whatever height it comes to (--topbar), and the stage is told.
export default class extends Controller {
  static targets = ["toggle"]

  connect() {
    this.observer = new ResizeObserver(() => this.measure())
    this.observer.observe(this.element)
    this.measure()
  }

  disconnect() {
    this.observer?.disconnect()
  }

  measure() {
    if (this.element.classList.contains("is-open")) return // a phone's open Menu lies over the page, not above it
    const height = Math.round(this.element.getBoundingClientRect().height)
    if (!height || this.height === height) return
    this.height = height
    document.documentElement.style.setProperty("--topbar", `${height}px`)
    window.dispatchEvent(new CustomEvent("layout:changed"))
  }

  toggle() {
    const open = !this.element.classList.contains("is-open")
    this.element.classList.toggle("is-open", open)
    this.toggleTarget.setAttribute("aria-expanded", String(open))
  }

  outside(event) {
    this.element.querySelectorAll("details[open]").forEach((menu) => { if (!menu.contains(event.target)) menu.open = false })
  }

  escape(event) {
    if (event.key === "Escape") this.element.querySelectorAll("details[open]").forEach((menu) => { menu.open = false })
  }
}
