import { Controller } from "@hotwired/stimulus"

// A grid form's less-used columns (data-advanced) stay hidden until asked for. Choosing a "When hit" moment
// brings them out, since "By" is one of them.
export default class extends Controller {
  static targets = ["table", "button"]

  toggle() {
    const simple = this.tableTarget.classList.toggle("grid-form--simple")
    this.buttonTarget.setAttribute("aria-pressed", String(!simple))
    this.buttonTarget.textContent = simple ? "More conditions" : "Fewer conditions"
  }

  reveal(event) {
    const asking = event.target.matches("select[name$='[when]']") && event.target.value === "hit"
    if (asking && this.tableTarget.classList.contains("grid-form--simple")) this.toggle()
  }
}
