import { Controller } from "@hotwired/stimulus"

// Submits its form as soon as a choice changes.
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
