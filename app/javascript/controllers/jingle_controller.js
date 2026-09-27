import { Controller } from "@hotwired/stimulus"
import { play } from "sound"

// Plays a jingle when it appears (a level up on the result panel). With a
// once key, only the first time on this device, so a reload stays quiet.
const PLAYED_KEY = "polychrome.jingles"

export default class extends Controller {
  static values = { name: String, once: String }

  connect() {
    if (this.onceValue && this.played) return
    this.played = true
    // After whatever fanfare is already playing.
    this.timer = setTimeout(() => play(this.nameValue), 400)
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  get played() {
    try { return JSON.parse(window.sessionStorage.getItem(PLAYED_KEY) || "[]").includes(this.onceValue) } catch { return false }
  }

  set played(_) {
    if (!this.onceValue) return
    try {
      const played = JSON.parse(window.sessionStorage.getItem(PLAYED_KEY) || "[]")
      window.sessionStorage.setItem(PLAYED_KEY, JSON.stringify([ ...played, this.onceValue ].slice(-50)))
    } catch { /* no storage: it plays again */ }
  }
}
