import { Controller } from "@hotwired/stimulus"
import { animate } from "animejs"
import { holdMusic, releaseMusic } from "sound"

// Someone awakens (Campaign#awaken!): the table stops, their face comes up,
// and turns over; the job is on the other side, with what they heard. The
// line's own cue plays the jingle (chat_line_controller). Click, or wait,
// to go on.
const FLIP_AFTER_MS = 1100
const HOLD_MS = 5200

export default class extends Controller {
  static targets = ["overlay", "wrap", "card", "portrait", "name", "line", "job", "description"]

  disconnect() {
    clearTimeout(this.timer)
    clearTimeout(this.flipTimer)
  }

  arrive(event) {
    const line = event.detail?.line
    if (!line || line.cueValue !== "awakening") return

    const card = line.cardValue || {}
    this.fillPortrait(card)
    this.nameTarget.textContent = card.name || ""
    this.lineTarget.textContent = card.line || ""
    this.lineTarget.hidden = !card.line
    this.jobTarget.textContent = card.job || ""
    this.descriptionTarget.textContent = card.description || ""
    this.show()
  }

  fillPortrait(card) {
    let face
    if (card.portrait) {
      face = document.createElement("img")
      face.src = card.portrait
      face.alt = ""
    } else {
      face = document.createElement("span")
      face.className = "awakening-card__plate"
      face.textContent = (card.name || "?").charAt(0)
      face.style.cssText = card.plate || ""
    }
    this.portraitTarget.replaceChildren(face)
  }

  show() {
    clearTimeout(this.timer)
    clearTimeout(this.flipTimer)
    this.cardTarget.classList.remove("is-turned")
    if (!this.overlayTarget.open) this.overlayTarget.showModal()
    holdMusic()
    const still = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    // The wrapper comes in; the card inside is left free to turn over (stage.css).
    if (!still) animate(this.wrapTarget, { scale: [0.6, 1], opacity: [0, 1], duration: 420, ease: "outBack" })
    this.flipTimer = setTimeout(() => this.turn(), still ? 0 : FLIP_AFTER_MS)
    this.timer = setTimeout(() => this.dismiss(), HOLD_MS)
  }

  // The face turns over (stage.css does the turning).
  turn() {
    // (the reduced-motion case turns at once too: stage.css drops the transition)
    this.cardTarget.classList.add("is-turned")
  }

  dismiss() {
    clearTimeout(this.timer)
    clearTimeout(this.flipTimer)
    if (this.overlayTarget.open) this.overlayTarget.close()
    releaseMusic()
  }
}
