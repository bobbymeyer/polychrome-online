import { Controller } from "@hotwired/stimulus"

// On a phone the top bar is one line: the links open from a Menu button.
export default class extends Controller {
  static targets = ["toggle"]

  toggle() {
    const open = !this.element.classList.contains("is-open")
    this.element.classList.toggle("is-open", open)
    this.toggleTarget.setAttribute("aria-expanded", String(open))
  }
}
