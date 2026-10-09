import { Controller } from "@hotwired/stimulus"
import { play } from "sound"

// A duel's meter (Duel, DuelMeter): Swing starts the needle across the
// meter and back; the next press (or Space, or Enter) stops it, and where it
// stopped goes to the server, which scores it. The position is read from the
// clock at the moment of the press, not the last drawn frame. The meter is
// data-turbo-permanent, so a refresh while it runs (the other side swinging)
// leaves it be; once swung, it lets go of that.
export default class extends Controller {
  static targets = ["needle", "button", "position", "form"]
  static values = { length: Number, sweep: Number }

  disconnect() {
    cancelAnimationFrame(this.frame)
  }

  press(event) {
    event.preventDefault()
    if (this.done) return
    if (this.started === undefined) return this.start()
    this.stop()
  }

  start() {
    this.started = performance.now()
    this.buttonTarget.textContent = "Stop"
    this.element.classList.add("is-swinging")
    const tick = () => {
      if (this.done) return
      this.place(this.at(performance.now()))
      this.frame = requestAnimationFrame(tick)
    }
    tick()
  }

  stop() {
    const position = this.at(performance.now())
    this.done = true
    cancelAnimationFrame(this.frame)
    this.place(position)
    this.element.classList.remove("is-swinging")
    this.element.classList.add("is-swung")
    this.buttonTarget.disabled = true
    this.buttonTarget.textContent = "Swung"
    play("blip")
    this.positionTarget.value = position.toFixed(1)
    // Swung, it needn't survive a refresh any more: the next one puts the swung meter in its place.
    this.element.removeAttribute("data-turbo-permanent")
    this.formTarget.requestSubmit()
  }

  // Across and back: a triangle wave over the meter's length.
  at(now) {
    const phase = ((now - this.started) / this.sweepValue) % 2
    return (phase <= 1 ? phase : 2 - phase) * this.lengthValue
  }

  place(position) {
    this.needleTarget.style.left = `${(position / this.lengthValue) * 100}%`
  }
}
