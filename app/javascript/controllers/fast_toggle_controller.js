import { Controller } from "@hotwired/stimulus"

// "Fast animations" in the account menu: a setting for this device, kept in
// this browser, that plays battles twice as fast. The battle player reads
// the same key (battle_player_controller) and hears the change as it's made.
const FAST_KEY = "polychrome.fastBattles"

export default class extends Controller {
  connect() {
    this.show(this.read())
  }

  toggle() {
    const fast = !this.read()
    try { localStorage.setItem(FAST_KEY, fast ? "1" : "0") } catch { /* private window: for this page only */ }
    this.show(fast)
    window.dispatchEvent(new CustomEvent("battle-fast:changed", { detail: { fast } }))
  }

  read() {
    try { return localStorage.getItem(FAST_KEY) === "1" } catch { return false }
  }

  show(fast) {
    this.element.setAttribute("aria-pressed", String(fast))
    this.element.classList.toggle("is-current", fast)
  }
}
