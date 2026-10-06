import { Controller } from "@hotwired/stimulus"

// What changed on the stage comes on with its transition, once. The stage
// is morphed on every table refresh, so each change is keyed
// (step and figure, or step and backdrop) and only plays the first time
// this page sees it; a figure leaving is gone at once after that.
const seen = new Set()

export default class extends Controller {
  connect() {
    this.play()
    // A refresh by morphing keeps this element and adds what's new inside it.
    this.onMorph = () => this.play()
    document.addEventListener("turbo:morph", this.onMorph)
  }

  disconnect() {
    document.removeEventListener("turbo:morph", this.onMorph)
  }

  play() {
    const items = [this.element, ...this.element.querySelectorAll("[data-arrive], [data-leave]")]
    for (const el of items) {
      const key = el.dataset.arriveKey || el.dataset.leaveKey
      if (!key) continue
      if (seen.has(key)) continue
      seen.add(key)
      if (el.dataset.arrive) el.classList.add("is-arriving")
      if (el.dataset.leave) el.classList.add("is-leaving")
    }
  }
}
