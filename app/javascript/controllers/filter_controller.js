import { Controller } from "@hotwired/stimulus"

// A live search over a list: as you type, the items (data-filter-target="item")
// whose text doesn't have the words are hidden. Empty shows all.
export default class extends Controller {
  static targets = ["input", "item"]

  apply() {
    const words = this.inputTarget.value.trim().toLowerCase().split(/\s+/).filter(Boolean)
    this.itemTargets.forEach((item) => {
      const text = item.textContent.toLowerCase()
      item.hidden = !words.every((word) => text.includes(word))
    })
  }
}
