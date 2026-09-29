import { Controller } from "@hotwired/stimulus"

// Tells the server this player has the battle in front of them, once the
// page's streams are listening (so the clock starting reaches it): the
// first round's clock waits for everyone (Battles::ArrivalsController).
const WAIT_MS = 5000

export default class extends Controller {
  static values = { url: String }

  connect() {
    this.started = Date.now()
    this.check()
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  check() {
    const listening = document.querySelectorAll("turbo-cable-stream-source").length > 0 &&
      !document.querySelector("turbo-cable-stream-source:not([connected])")
    if (listening || Date.now() - this.started > WAIT_MS) return this.arrive()
    this.timer = setTimeout(() => this.check(), 150)
  }

  arrive() {
    const token = document.querySelector("meta[name=csrf-token]")?.content
    fetch(this.urlValue, { method: "POST", headers: { "X-CSRF-Token": token }, credentials: "same-origin" })
  }
}
