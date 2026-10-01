import { Controller } from "@hotwired/stimulus"

// What a player looks up at the table (the map, the party, what they know):
// a row of tabs over closed panels, one open at a time, and pressing the open
// one closes it again. What they can do now stays in front.
export default class extends Controller {
  static targets = ["tab", "panel"]
  // On a wide screen, the one that starts open (a player's map, as the scene's art).
  static values = { wide: String }

  connect() {
    if (this.wideValue && window.matchMedia("(min-width: 1100px)").matches) this.show(this.wideValue)
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
