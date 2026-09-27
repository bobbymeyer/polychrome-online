import { Controller } from "@hotwired/stimulus"
import { muted, setMuted } from "sound"

// Sound on or off, for this device (sound.js).
export default class extends Controller {
  connect() {
    this.show()
  }

  toggle() {
    setMuted(!muted())
    this.show()
  }

  show() {
    const off = muted()
    this.element.textContent = off ? "Sound off" : "Sound on"
    this.element.setAttribute("aria-pressed", String(off))
  }
}
