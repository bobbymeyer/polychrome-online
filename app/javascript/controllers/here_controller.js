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
    // A refresh by morphing puts the server's words back.
    this.onMorph = () => this.check()
    document.addEventListener("turbo:morph", this.onMorph)
  }

  disconnect() {
    clearInterval(this.timer)
    document.removeEventListener("turbo:morph", this.onMorph)
  }

  whoTargetConnected() {
    this.check()
  }

  check() {
    this.whoTargets.forEach((who) => {
      const seen = Date.parse(who.dataset.seenAt || "")
      const here = !Number.isNaN(seen) && Date.now() - seen < HERE_MS
      who.classList.toggle("is-here", here)
      // The party panel's mark says "here" or "away"; a row can bring its own words ("Waiting on their player|Their player is away").
      const [present, gone] = (who.dataset.hereWords || "here|away").split("|")
      who.textContent = here ? present : gone
    })
  }
}
