import { Controller } from "@hotwired/stimulus"

// The table's open choice (app/views/choices/_panel). It waits for the
// dialogue box, so a scene's lines are read before the choice comes up.
// The panel is the same for the whole table; this marks the option the
// seat's own character picked.
export default class extends Controller {
  static targets = ["panel", "option"]

  optionTargetConnected(option) {
    const mine = this.element.closest(".table")?.dataset.seatCharacter
    const picked = Boolean(mine) && option.dataset.pickedBy.split(" ").includes(mine)
    option.classList.toggle("is-mine", picked)
    option.querySelector(".choice__mine").hidden = !picked
    option.querySelector(".choice__pick")?.setAttribute("aria-pressed", picked)
  }

  panelTargetConnected(panel) {
    const reveal = () => {
      if (document.documentElement.dataset.dialogueBusy === "true") return (this.timer = setTimeout(reveal, 250))
      panel.hidden = false
      const smooth = !window.matchMedia("(prefers-reduced-motion: reduce)").matches
      panel.scrollIntoView({ block: "nearest", behavior: smooth ? "smooth" : "auto" })
    }
    // Lines sent with the choice can land just after it.
    this.timer = setTimeout(reveal, 400)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
