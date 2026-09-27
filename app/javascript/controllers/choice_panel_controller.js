import { Controller } from "@hotwired/stimulus"

// The table's open choice (app/views/choices/_panel). It waits for the
// dialogue box, so a scene's lines are read before the choice comes up.
export default class extends Controller {
  static targets = ["panel"]

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
