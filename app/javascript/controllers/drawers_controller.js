import { Controller } from "@hotwired/stimulus"

// What a player looks up at the table (the map, the party, what they know):
// a row of tabs over closed panels, one open at a time, and pressing the open
// one closes it again. What they can do now stays in front.
export default class extends Controller {
  static targets = ["tab", "panel"]

  toggle(event) {
    const key = event.currentTarget.dataset.key
    const opening = event.currentTarget.getAttribute("aria-expanded") !== "true"
    this.tabTargets.forEach((tab) => tab.setAttribute("aria-expanded", String(opening && tab.dataset.key === key)))
    this.panelTargets.forEach((panel) => { panel.hidden = !(opening && panel.dataset.key === key) })
  }
}
