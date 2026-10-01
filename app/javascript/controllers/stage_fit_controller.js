import { Controller } from "@hotwired/stimulus"

// The Stage fits the screen without scrolling (docs/DESIGN.md, "The Stage"):
// it measures how far down the page the frame starts (the top bar, the head,
// the Now line, which change height as the table changes) and tells the
// stylesheet, which sizes the frame to the room left under it, keeping 16:9.
// Narrower than its column, the column wins (stage.css).
export default class extends Controller {
  static values = { below: { type: Number, default: 48 } } // room to leave under the frame (its caption)

  connect() {
    this.fit = () => this.measure()
    window.addEventListener("resize", this.fit)
    this.observer = new ResizeObserver(this.fit)
    if (this.element.parentElement) this.observer.observe(this.element.parentElement)
    this.measure()
  }

  disconnect() {
    window.removeEventListener("resize", this.fit)
    this.observer?.disconnect()
  }

  measure() {
    const top = Math.round(this.element.getBoundingClientRect().top + window.scrollY)
    this.element.style.setProperty("--stage-top", `${top}px`)
    this.element.style.setProperty("--stage-below", `${this.belowValue}px`)
  }
}
