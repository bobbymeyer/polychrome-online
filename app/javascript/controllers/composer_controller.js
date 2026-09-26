import { Controller } from "@hotwired/stimulus"

// Enter sends, Shift+Enter starts a new line.
export default class extends Controller {
  static targets = ["body"]

  key(event) {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing || event.target !== this.bodyTarget) return

    event.preventDefault()
    if (this.bodyTarget.value.trim()) this.element.requestSubmit()
  }
}
