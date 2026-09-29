import { Controller } from "@hotwired/stimulus"

// A "New …" form kept through page refreshes (data-turbo-permanent, so a
// half-written clock survives someone else's change) still starts fresh
// once its own entry is made: cleared, and folded away.
export default class extends Controller {
  done(event) {
    if (!event.detail.success) return
    this.element.querySelectorAll("form").forEach((form) => form.reset())
    if (this.element.tagName === "DETAILS") this.element.open = false
  }
}
