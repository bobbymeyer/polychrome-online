import { Controller } from "@hotwired/stimulus"
import { animate } from "animejs"
import { play } from "sound"

// A boss's entrance (docs/DESIGN.md, "The stage"): the room goes quiet, its
// name is slammed across the stage, and it has the first word. Plays once per
// viewer per battle, and only while the fight hasn't really begun, so a
// reload in round 4 doesn't stop the show.
const HOLD_MS = 1800
const SEEN_KEY = "polychrome.bossSeen"

export default class extends Controller {
  static targets = ["card"]
  static values = { key: String, fresh: Boolean, name: String, line: String, plate: String }

  connect() {
    if (!this.freshValue || this.seen) return
    this.seen = true
    // Let the wipe clear the screen first.
    this.timer = setTimeout(() => this.enter(), 700)
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  enter() {
    window.dispatchEvent(new CustomEvent("stage:boss-intro"))
    play("boss-intro")
    const card = this.cardTarget
    this.element.hidden = false

    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.timer = setTimeout(() => this.leave(), HOLD_MS)
      return
    }
    animate(card, { translateX: ["-110%", "0%"], skewX: [-18, -8], duration: 380, ease: "outExpo" })
    animate(card.querySelector(".boss-card__name"), { scale: [1.6, 1], opacity: [0, 1], duration: 420, delay: 160, ease: "outBack" })
    this.timer = setTimeout(() => {
      animate(card, { translateX: ["0%", "120%"], duration: 320, ease: "inQuad" })
      this.timer = setTimeout(() => this.leave(), 320)
    }, HOLD_MS)
  }

  leave() {
    this.element.hidden = true
    if (this.lineValue) {
      window.dispatchEvent(new CustomEvent("dialogue:say", {
        detail: { speaker: this.nameValue, text: this.lineValue, plate: this.plateValue, expression: "angry" }
      }))
    }
  }

  skip() {
    clearTimeout(this.timer)
    this.leave()
  }

  get seen() {
    try { return JSON.parse(window.sessionStorage.getItem(SEEN_KEY) || "[]").includes(this.keyValue) } catch { return false }
  }

  set seen(_) {
    try {
      const seen = JSON.parse(window.sessionStorage.getItem(SEEN_KEY) || "[]")
      window.sessionStorage.setItem(SEEN_KEY, JSON.stringify([ ...seen, this.keyValue ].slice(-20)))
    } catch { /* private mode: it plays again, no harm */ }
  }
}
