import { Controller } from "@hotwired/stimulus"

// The table's middle column: the Stage stays put and what's under it (the
// Controls) scrolls on its own. A wheel anywhere in the column scrolls the
// Controls, so nobody has to find the scrolling part first.
export default class extends Controller {
  static targets = ["under"]

  wheel(event) {
    if (!this.hasUnderTarget || this.underTarget.contains(event.target)) return // already theirs
    this.underTarget.scrollBy({ top: event.deltaY })
  }
}
