import { Controller } from "@hotwired/stimulus"

// An "every one" box over a list of boxes: ticking it ticks them all, and
// it's ticked exactly when they all are.
export default class extends Controller {
  static targets = ["all", "one"]

  all() {
    this.oneTargets.forEach((box) => { box.checked = this.allTarget.checked })
  }

  one() {
    this.allTarget.checked = this.oneTargets.every((box) => box.checked)
  }
}
