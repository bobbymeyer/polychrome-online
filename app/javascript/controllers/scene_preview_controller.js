import { Controller } from "@hotwired/stimulus"

// The preview on a scene's page, run through as the table will see it: the
// line types out in the box (click to finish), and while playing, the next
// step follows at reading pace (a change passes quickly; a choice stops,
// as it does at the table). Each step is a frame load, so the page's
// "playing" rides the link to the next one.
const TYPE_MS = 22

export default class extends Controller {
  static targets = ["text", "next"]
  static values = { playing: Boolean, seconds: Number, stops: Boolean }

  connect() {
    this.type()
    if (this.playingValue && !this.stopsValue && this.hasNextTarget) {
      this.timer = setTimeout(() => this.advance(), this.secondsValue * 1000)
    }
  }

  disconnect() {
    clearTimeout(this.timer)
    clearInterval(this.typing)
  }

  type() {
    if (!this.hasTextTarget) return
    const full = this.textTarget.textContent
    this.textTarget.textContent = ""
    let shown = 0
    this.typing = setInterval(() => {
      shown += 1
      this.textTarget.textContent = full.slice(0, shown)
      if (shown >= full.length) this.finish()
    }, TYPE_MS)
    this.full = full
  }

  finish() {
    clearInterval(this.typing)
    if (this.hasTextTarget && this.full) this.textTarget.textContent = this.full
  }

  advance() {
    const url = new URL(this.nextTarget.href, location.href)
    url.searchParams.set("playing", "1")
    this.nextTarget.href = url.toString()
    this.nextTarget.click()
  }
}
