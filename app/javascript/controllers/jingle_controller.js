import { Controller } from "@hotwired/stimulus"
import { play } from "sound"
import { seen, markSeen } from "storage"

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
    return seen(PLAYED_KEY, this.onceValue, { session: true })
  }

  set played(_) {
    if (this.onceValue) markSeen(PLAYED_KEY, this.onceValue, { cap: 50, session: true }) // no storage: it plays again
  }
}
