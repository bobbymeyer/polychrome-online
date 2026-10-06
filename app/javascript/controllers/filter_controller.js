import { Controller } from "@hotwired/stimulus"

// A live search over a list: as you type, the items (data-filter-target="item")
// whose text doesn't have the words are hidden. Empty shows all. An item that
// arrives while a search is on (a log line, live) is held to it too.
export default class extends Controller {
  static targets = ["input", "item"]

  apply() {
    this.itemTargets.forEach((item) => this.judge(item, this.words))
  }

  itemTargetConnected(item) {
    const words = this.words
    if (words.length) this.judge(item, words)
  }

  get words() {
    return this.inputTarget.value.trim().toLowerCase().split(/\s+/).filter(Boolean)
  }

  judge(item, words) {
    const text = item.textContent.toLowerCase()
    item.hidden = !words.every((word) => text.includes(word))
  }
}
