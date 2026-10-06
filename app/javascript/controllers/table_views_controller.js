import { Controller } from "@hotwired/stimulus"
import { get, set } from "storage"

// The table on a phone or a tablet (docs/DESIGN.md, "Phones"): the three
// columns (you and the party; the stage and what you can do; the log) are
// three views, picked from a strip in the top bar (this element). This sets
// which on the table (#table's data-table-view, stage.css shows one) and
// remembers it for this campaign in this tab. Wider than a tablet the strip
// is hidden and the attribute changes nothing.
//
// It talks to the table by events, never by its controllers: each change
// goes out as table-views:changed on window (detail: { key }), and the log
// drawer and the drawers answer for themselves (log_drawer_controller#view,
// drawers_controller#view). The log drawer says how many lines are unread
// (log-drawer:unread, detail: { count }) and the strip wears that on its Log
// tab. Anything on the table can ask for a view with table-views:show
// (detail: { key }).
export default class extends Controller {
  static targets = ["tab", "badge"]
  static values = { key: String }

  connect() {
    this.table = document.getElementById("table")
    if (!this.table) return
    this.show(this.remembered() || "stage", { remember: false })
    // The drawer says its count as it connects; whichever of us came second, the badge is right.
    const count = this.table.querySelector(".log-drawer__count")
    if (count) this.showBadge(count.hidden ? 0 : Number(count.textContent) || 0)
  }

  pick(event) {
    this.show(event.currentTarget.dataset.key)
  }

  // Something on the table asks for a view (a whisper takes the GM to the talk box on the stage).
  go(event) {
    this.show(event.detail.key)
  }

  show(key, { remember = true } = {}) {
    if (!this.tabTargets.some((tab) => tab.dataset.key === key)) key = "stage"
    this.table.dataset.tableView = key
    this.tabTargets.forEach((tab) => tab.setAttribute("aria-current", tab.dataset.key === key ? "page" : "false"))
    window.dispatchEvent(new CustomEvent("table-views:changed", { detail: { key } }))
    if (remember) this.rememberView(key)
  }

  unread(event) {
    this.showBadge(event.detail.count)
  }

  showBadge(count) {
    if (!this.hasBadgeTarget) return
    this.badgeTarget.textContent = count > 99 ? "99+" : String(count)
    this.badgeTarget.hidden = count === 0
  }

  get storageKey() {
    return `polychrome.tableView.${this.keyValue}`
  }

  remembered() {
    return get(this.storageKey, { session: true })
  }

  rememberView(key) {
    set(this.storageKey, key, { session: true }) // no storage: the stage it is, next time
  }
}
