import { Controller } from "@hotwired/stimulus"

// A form's problems come into view and take focus as the refused save is drawn, so a long form doesn't leave
// them above the fold.
export default class extends Controller {
  connect() {
    this.element.scrollIntoView({ block: "start" })
    this.element.focus({ preventScroll: true })
  }
}
