import { Controller } from "@hotwired/stimulus"

// "Timing meter" in the account menu: a setting for this device, kept in this
// browser, that runs the meter on each move in a battle (timing_meter_controller
// reads the same key). Off by default for people who asked for reduced motion.
const SETTING_KEY = "polychrome.meter"

export default class extends Controller {
  connect() {
    this.show(this.read())
  }

  toggle() {
    const on = !this.read()
    try { localStorage.setItem(SETTING_KEY, on ? "on" : "off") } catch { /* private window: for this page only */ }
    this.show(on)
  }

  read() {
    let saved = null
    try { saved = localStorage.getItem(SETTING_KEY) } catch { /* no storage */ }
    if (saved) return saved === "on"
    return !window.matchMedia("(prefers-reduced-motion: reduce)").matches
  }

  show(on) {
    this.element.setAttribute("aria-pressed", String(on))
    this.element.classList.toggle("is-current", on)
  }
}
