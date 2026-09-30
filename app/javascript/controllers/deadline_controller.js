import { Controller } from "@hotwired/stimulus"
import { animate } from "animejs"

// A deadline passes (Clock#fill!): the table stops for it. The date drops
// in, the clock's line is slammed across the stage in big type, and what
// the place has become sits under it. The line's own cue plays the bell
// (chat_line_controller). Click, or wait, to go on.
const HOLD_MS = 4200

export default class extends Controller {
  static targets = ["overlay", "date", "line", "place"]

  disconnect() {
    clearTimeout(this.timer)
  }

  arrive(event) {
    const line = event.detail?.line
    if (!line || line.cueValue !== "deadline") return

    const card = line.cardValue || {}
    this.dateTarget.textContent = card.date || ""
    this.lineTarget.textContent = card.line || line.text
    this.placeTarget.textContent = card.place || ""
    this.placeTarget.hidden = !card.place
    this.show()
  }

  show() {
    clearTimeout(this.timer)
    if (!this.overlayTarget.open) this.overlayTarget.showModal()
    if (!window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      animate(this.dateTarget, { translateY: ["-120%", "0%"], opacity: [0, 1], duration: 360, ease: "outExpo" })
      animate(this.lineTarget, { scale: [1.5, 1], opacity: [0, 1], duration: 460, delay: 220, ease: "outBack" })
      animate(this.placeTarget, { translateX: ["-40px", "0px"], opacity: [0, 1], duration: 320, delay: 620, ease: "outQuad" })
    }
    this.timer = setTimeout(() => this.dismiss(), HOLD_MS)
  }

  dismiss() {
    clearTimeout(this.timer)
    if (this.overlayTarget.open) this.overlayTarget.close()
  }
}
