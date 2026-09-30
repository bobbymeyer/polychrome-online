import { Controller } from "@hotwired/stimulus"

// Changing job (characters/_jobs): when the new job can't use something
// the character is wearing, the form asks first, naming what comes off.
export default class extends Controller {
  static targets = ["select"]

  pick() {
    const drops = this.selectTarget.selectedOptions[0]?.dataset.drops
    if (drops) this.element.dataset.turboConfirm = `Change archetype? ${drops} can't be used and go${drops.includes(" and ") || drops.includes(",") ? "" : "es"} back to the bag.`
    else delete this.element.dataset.turboConfirm
  }

  connect() {
    this.pick()
  }
}
