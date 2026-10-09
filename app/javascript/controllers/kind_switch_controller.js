import { Controller } from "@hotwired/stimulus"

// A form whose fields depend on a kind: anything marked
// data-show-for="kind another_kind" shows only while the kind select is one
// of those. Hidden fields still submit, blank, so the server decides what
// a kind keeps.
export default class extends Controller {
  static targets = ["select"]

  connect() {
    this.update()
  }

  update() {
    if (!this.hasSelectTarget) return // a form with nothing to switch on (a say step)
    const kind = this.selectTarget.value
    this.element.querySelectorAll("[data-show-for]").forEach((el) => {
      el.hidden = !el.dataset.showFor.split(" ").includes(kind)
    })
  }
}
