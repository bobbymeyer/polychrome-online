import { Controller } from "@hotwired/stimulus"

// Someone has the battle in front of them (BattleRecord#watch!): said when
// the page opens and every 20 seconds while it's showing. With nobody
// saying so, the round's clock holds instead of running the round.
const BEAT_MS = 20000

export default class extends Controller {
  static values = { url: String }

  connect() {
    this.beat()
    this.timer = setInterval(() => this.beat(), BEAT_MS)
    this.onShow = () => this.beat()
    document.addEventListener("visibilitychange", this.onShow)
  }

  disconnect() {
    clearInterval(this.timer)
    document.removeEventListener("visibilitychange", this.onShow)
  }

  // A tab in the background isn't watching.
  beat() {
    if (document.visibilityState !== "visible") return

    const token = document.querySelector("meta[name=csrf-token]")?.content
    fetch(this.urlValue, { method: "PATCH", headers: { "X-CSRF-Token": token }, credentials: "same-origin" }).catch(() => {})
  }
}
