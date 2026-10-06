import { Controller } from "@hotwired/stimulus"

// The table on a phone or a tablet (docs/DESIGN.md, "Phones"): the three
// columns (you and the party; the stage and what you can do; the log) are
// three views, picked from a strip in the top bar (this element). This sets
// which on the table (data-table-view, stage.css shows one), remembers it for
// this campaign in this tab, and wires the log view to the log drawer:
// inline, awake, scrolled to its newest line, with the drawer's count of new
// lines on the strip. Wider than a tablet the strip is hidden and the
// attribute changes nothing.
const NARROW = "(max-width: 1099px)"

export default class extends Controller {
  static targets = ["tab", "badge"]
  static values = { key: String }

  connect() {
    this.table = document.querySelector(".table")
    if (!this.table) return
    this.show(this.remembered() || "stage", { remember: false })
    const count = this.table.querySelector(".log-drawer__count")
    if (count) {
      this.observer = new MutationObserver(() => this.mirror(count))
      this.observer.observe(count, { childList: true, characterData: true, attributes: true, subtree: true })
      this.mirror(count)
    }
  }

  disconnect() {
    this.observer?.disconnect()
  }

  pick(event) {
    this.show(event.currentTarget.dataset.key)
  }

  show(key, { remember = true } = {}) {
    if (!this.tabTargets.some((tab) => tab.dataset.key === key)) key = "stage"
    this.table.dataset.tableView = key
    this.tabTargets.forEach((tab) => tab.setAttribute("aria-current", tab.dataset.key === key ? "page" : "false"))
    this.wakeLog(key === "log")
    if (key === "party") this.openParty()
    if (remember) this.rememberView(key)
  }

  // The party view starts on the party, not on two closed tabs: the drawers open it unless one is open already.
  openParty() {
    if (!this.phone()) return
    const drawers = this.table.querySelector(".drawers")
    const controller = drawers && this.application.getControllerForElementAndIdentifier(drawers, "drawers")
    if (controller && !drawers.querySelector("[aria-expanded=true]")) controller.show("party")
  }

  // The log drawer's panel is inert while the drawer is closed; as a view it has to take touches and focus,
  // so the view opens the drawer (which also scrolls it to its newest line and clears its count) and closes
  // it on leaving. Wider than a tablet the drawer is its own, and this leaves it alone.
  wakeLog(on) {
    if (!this.phone()) return
    const drawer = this.table.querySelector(".log-drawer")
    const controller = drawer && this.application.getControllerForElementAndIdentifier(drawer, "log-drawer")
    if (!controller) return
    if (on) controller.open({ focus: false })
    else if (drawer.classList.contains("is-open")) controller.close()
  }

  phone() {
    return window.matchMedia(NARROW).matches
  }

  mirror(count) {
    if (!this.hasBadgeTarget) return
    this.badgeTarget.textContent = count.textContent
    this.badgeTarget.hidden = count.hidden || !count.textContent.trim()
  }

  get storageKey() {
    return `polychrome.tableView.${this.keyValue}`
  }

  remembered() {
    try { return sessionStorage.getItem(this.storageKey) } catch { return null }
  }

  rememberView(key) {
    try { sessionStorage.setItem(this.storageKey, key) } catch { /* no storage: the stage it is, next time */ }
  }
}
