import { Controller } from "@hotwired/stimulus"

// The Stage fits the screen without scrolling (docs/DESIGN.md, "The Stage"):
// it measures how far down the page the frame starts (under the top bar) and
// tells the stylesheet (--stage-top, on the page, so the columns can take the
// same height), which sizes the frame to the room left under it, keeping
// 16:9. Narrower than its column, the column wins (stage.css).
export default class extends Controller {
  static values = { below: { type: Number, default: 48 } } // room to leave under the frame (its caption)

  connect() {
    this.fit = () => this.measure()
    window.addEventListener("resize", this.fit)
    window.addEventListener("layout:changed", this.fit) // the top bar's height, measured
    this.observer = new ResizeObserver(this.fit)
    if (this.element.parentElement) this.observer.observe(this.element.parentElement)
    this.measure()
  }

  disconnect() {
    window.removeEventListener("resize", this.fit)
    window.removeEventListener("layout:changed", this.fit)
    this.observer?.disconnect()
  }

  measure() {
    const top = Math.round(this.element.getBoundingClientRect().top + window.scrollY)
    document.documentElement.style.setProperty("--stage-top", `${top}px`)
    this.element.style.setProperty("--stage-below", `${this.belowValue}px`)
  }
}
