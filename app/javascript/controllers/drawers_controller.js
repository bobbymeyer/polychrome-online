import { Controller } from "@hotwired/stimulus"
import { narrow } from "screen"

// What a player looks up at the table (the map, the party, what they know):
// a row of tabs over closed panels, one open at a time, and pressing the open
// one closes it again. What they can do now stays in front.
//
// On a phone or a tablet the party view (table_views_controller) starts on
// the party, not on two closed tabs: it hears which view is up and opens the
// party panel for "party" unless one is open already.
export default class extends Controller {
  static targets = ["tab", "panel"]
  // On a wide screen, the one that starts open (a player's map, as the scene's art).
  static values = { wide: String }

  connect() {
    // A link into a panel (#secrets, from the table) opens it; else, on a wide screen, the one that starts open.
    if (!this.follow() && this.wideValue && !narrow()) this.show(this.wideValue)
    this.onHash = () => this.follow()
    window.addEventListener("hashchange", this.onHash)
    // The table may have picked its view before this connected: the attribute says which.
    this.view({ detail: { key: this.element.closest("[data-table-view]")?.dataset.tableView } })
  }

  // A view of the table was picked (table-views:changed).
  view(event) {
    if (event.detail.key !== "party" || !narrow()) return
    if (!this.tabTargets.some((tab) => tab.getAttribute("aria-expanded") === "true")) this.show("party")
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
