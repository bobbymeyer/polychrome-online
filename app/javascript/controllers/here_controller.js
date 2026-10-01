import { Controller } from "@hotwired/stimulus"

// The party panel's "here" marks (campaigns/tables/_party): a player who
// stops saying they're here (heartbeat_controller) is shown away once a
// minute has gone, without waiting for the panel to be sent again.
const HERE_MS = 60000

export default class extends Controller {
  static targets = ["who"]

  connect() {
    this.check()
    this.timer = setInterval(() => this.check(), 15000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  whoTargetConnected() {
    this.check()
  }

  check() {
    this.whoTargets.forEach((who) => {
      const seen = Date.parse(who.dataset.seenAt || "")
      const here = !Number.isNaN(seen) && Date.now() - seen < HERE_MS
      who.classList.toggle("is-here", here)
      who.textContent = here ? "here" : "away"
    })
  }
}
