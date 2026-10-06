import { Controller } from "@hotwired/stimulus"

// The top bar: on a phone its links open from a Menu button; the account's
// menu (your name) closes on a click elsewhere or Esc. It sticks to the top in
// the page's flow (application.css), so nothing measures it.
export default class extends Controller {
  static targets = ["toggle"]

  toggle() {
    const open = !this.element.classList.contains("is-open")
    this.element.classList.toggle("is-open", open)
    this.toggleTarget.setAttribute("aria-expanded", String(open))
  }

  outside(event) {
    this.element.querySelectorAll("details[open]").forEach((menu) => { if (!menu.contains(event.target)) menu.open = false })
  }

  escape(event) {
    if (event.key === "Escape") this.element.querySelectorAll("details[open]").forEach((menu) => { menu.open = false })
  }
}
