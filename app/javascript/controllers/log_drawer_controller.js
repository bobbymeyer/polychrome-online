import { Controller } from "@hotwired/stimulus"

// The game log in a drawer on the right edge (app/views/shared/_log_drawer).
// Closed by default; the tab or L slides it open, and Esc or L closes it.
// While it's closed, the tab counts the lines that arrive and gives a pulse,
// so nothing happens unseen.
export default class extends Controller {
  static targets = ["panel", "tab", "count", "list"]
  // Your own lines aren't news to you: they don't count.
  static values = { self: String }

  connect() {
    this.unread = 0
    this.observer = new MutationObserver((mutations) => this.arrived(mutations))
    this.listTargets.forEach((list) => this.observer.observe(list, { childList: true }))
  }

  disconnect() {
    this.observer?.disconnect()
  }

  get isOpen() {
    return this.element.classList.contains("is-open")
  }

  toggle() {
    this.isOpen ? this.close() : this.open()
  }

  open() {
    this.element.classList.add("is-open")
    this.panelTarget.inert = false
    this.tabTarget.setAttribute("aria-expanded", "true")
    this.unread = 0
    this.showCount()
    this.scrollToEnd()
    this.panelTarget.querySelector("button")?.focus({ preventScroll: true })
  }

  close() {
    const hadFocus = this.panelTarget.contains(document.activeElement)
    this.element.classList.remove("is-open")
    this.panelTarget.inert = true
    this.tabTarget.setAttribute("aria-expanded", "false")
    if (hadFocus) this.tabTarget.focus({ preventScroll: true })
  }

  // L toggles, Esc closes. Runs in the capture phase so an open drawer's Esc
  // doesn't also count as "back" in a battle menu.
  key(event) {
    if (event.altKey || event.ctrlKey || event.metaKey) return
    if (event.target.closest?.("input, textarea, select, [contenteditable]")) return
    if (event.key === "l" || event.key === "L") {
      event.preventDefault()
      this.toggle()
    } else if (event.key === "Escape" && this.isOpen) {
      event.preventDefault()
      event.stopImmediatePropagation()
      this.close()
    }
  }

  arrived(mutations) {
    const added = mutations.reduce((n, m) => n + [...m.addedNodes].filter((node) => node.nodeType === Node.ELEMENT_NODE && !this.mine(node)).length, 0)
    if (!added) return
    if (this.isOpen) return this.scrollToEnd()

    this.unread += added
    this.showCount()
    this.tabTarget.classList.remove("is-pulsing")
    void this.tabTarget.offsetWidth // restart the pulse
    this.tabTarget.classList.add("is-pulsing")
  }

  mine(node) {
    return this.selfValue !== "" && node.dataset?.chatLineSpeakerValue === this.selfValue
  }

  showCount() {
    this.countTarget.hidden = this.unread === 0
    this.countTarget.textContent = this.unread > 99 ? "99+" : String(this.unread)
  }

  scrollToEnd() {
    this.listTargets.forEach((list) => { list.parentElement.scrollTop = list.parentElement.scrollHeight })
  }
}
