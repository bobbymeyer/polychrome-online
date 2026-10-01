import { Controller } from "@hotwired/stimulus"

// Someone has the page in front of them: said when it opens and every 20
// seconds while it's showing. On a battle (BattleRecord#watch!), with nobody
// saying so, the round's clock holds; at the table (Character#seen!), the
// party panel says who is here.
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
