import { Controller } from "@hotwired/stimulus"

// What a player looks up at the table (the map, the party, what they know):
// a row of tabs over closed panels, one open at a time, and pressing the open
// one closes it again. What they can do now stays in front.
export default class extends Controller {
  static targets = ["tab", "panel"]
  // On a wide screen, the one that starts open (a player's map, as the scene's art).
  static values = { wide: String }

  connect() {
    // A link into a panel (#secrets, from the table) opens it; else, on a wide screen, the one that starts open.
    if (!this.follow() && this.wideValue && window.matchMedia("(min-width: 1100px)").matches) this.show(this.wideValue)
    this.onHash = () => this.follow()
    window.addEventListener("hashchange", this.onHash)
  }

  disconnect() {
    window.removeEventListener("hashchange", this.onHash)
  }

  // The panel the address names (its key, or an id inside it), opened and brought into view.
  follow() {
    const wanted = decodeURIComponent(window.location.hash.slice(1))
    if (!wanted) return false
    const panel = this.panelTargets.find((p) => p.dataset.key === wanted || p.querySelector(`#${CSS.escape(wanted)}`))
    if (!panel) return false
    this.show(panel.dataset.key)
    panel.scrollIntoView({ block: "start" })
    return true
  }

  toggle(event) {
    const opening = event.currentTarget.getAttribute("aria-expanded") !== "true"
    this.show(opening ? event.currentTarget.dataset.key : null)
  }

  show(key) {
    this.tabTargets.forEach((tab) => tab.setAttribute("aria-expanded", String(tab.dataset.key === key)))
    this.panelTargets.forEach((panel) => { panel.hidden = panel.dataset.key !== key })
  }
}
