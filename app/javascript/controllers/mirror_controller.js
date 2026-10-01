import { Controller } from "@hotwired/stimulus"

// A copy of something live elsewhere on the page, kept in step: the
// table's "You" line shows your row's HP and MP from the party panel,
// which the table's broadcasts replace.
export default class extends Controller {
  static targets = ["slot"]
  static values = { from: String }

  connect() {
    this.observer = new MutationObserver(() => this.copy())
    this.observer.observe(this.element.closest(".table") || document.body, { childList: true, subtree: true })
  }

  disconnect() {
    this.observer.disconnect()
  }

  copy() {
    const source = document.querySelector(this.fromValue)
    if (!source || source.outerHTML === this.copied) return
    this.copied = source.outerHTML
    const copy = source.cloneNode(true)
    copy.removeAttribute("id") // the panel's is the one broadcasts look for
    this.slotTarget.replaceChildren(copy)
  }
}
