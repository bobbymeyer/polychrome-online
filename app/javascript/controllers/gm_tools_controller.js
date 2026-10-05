import { Controller } from "@hotwired/stimulus"

// The rest of the GM's tools at the table (campaigns/tables/gm/_tools), called
// from the strip like the other controls: one tab at a time, and the one you
// had open stays open, across reloads and the table's own refreshes, for this
// campaign in this browser.
export default class extends Controller {
  static targets = ["tab", "panel"]
  static values = { campaign: Number }

  connect() {
    this.show(this.stored() || this.tabTargets[0]?.dataset.key)
    // A refresh by morphing puts the server's first tab back: keep ours.
    this.onMorph = () => this.show(this.current)
    document.addEventListener("turbo:morph", this.onMorph)
  }

  disconnect() {
    document.removeEventListener("turbo:morph", this.onMorph)
  }

  pick(event) {
    this.show(event.currentTarget.dataset.key)
    this.store(this.current)
  }

  // Left and right move between tabs, as tabs do.
  arrow(event) {
    const step = { ArrowRight: 1, ArrowLeft: -1 }[event.key]
    if (!step) return
    event.preventDefault()
    const tabs = this.tabTargets
    const next = tabs[(tabs.indexOf(event.currentTarget) + step + tabs.length) % tabs.length]
    this.show(next.dataset.key)
    this.store(this.current)
    next.focus()
  }

  show(key) {
    if (!this.tabTargets.some((tab) => tab.dataset.key === key)) key = this.tabTargets[0]?.dataset.key
    this.current = key
    this.tabTargets.forEach((tab) => {
      const on = tab.dataset.key === key
      tab.setAttribute("aria-selected", String(on))
      tab.tabIndex = on ? 0 : -1
    })
    this.panelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.key !== key
      // A panel fetched when opened (the Moves tab): opening it is the moment, wherever it sits on the page.
      if (!panel.hidden) panel.querySelectorAll("turbo-frame[loading=lazy]").forEach((frame) => { frame.loading = "eager" })
    })
  }

  get storageKey() {
    return `polychrome.gmTools.${this.campaignValue}`
  }

  stored() {
    try { return localStorage.getItem(this.storageKey) } catch { return null }
  }

  store(key) {
    try { localStorage.setItem(this.storageKey, key) } catch { /* private window: the first tab it is */ }
  }
}
