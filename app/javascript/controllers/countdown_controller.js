import { Controller } from "@hotwired/stimulus"

// Shows the time left on the round's input timer. Display only: the
// server's timeout job is what actually ends the round.
export default class extends Controller {
  static targets = ["clock"]
  static values = { deadline: String }

  connect() {
    this.tick()
    this.timer = setInterval(() => this.tick(), 1000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  tick() {
    const left = Math.max(0, Math.round((new Date(this.deadlineValue) - Date.now()) / 1000))
    this.clockTarget.textContent = left > 0 ? `${Math.floor(left / 60)}:${String(left % 60).padStart(2, "0")}` : "Time's up"
    this.element.classList.toggle("is-urgent", left <= 10)
  }
}
