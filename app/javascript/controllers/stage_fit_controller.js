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
    // Anything that moves the frame's top (the top bar settling, a notice coming and going, fonts arriving)
    // changes the page's height too: the page is watched, and the frame measured again.
    this.observer = new ResizeObserver(this.fit)
    for (const el of [ document.body, document.querySelector(".topbar"), this.element.closest(".page"), this.element.parentElement ]) if (el) this.observer.observe(el)
    // And anything put in or taken out of the page (a notice, a panel replaced live): measured again next frame.
    this.mutations = new MutationObserver(() => { cancelAnimationFrame(this.raf); this.raf = requestAnimationFrame(this.fit) })
    this.mutations.observe(document.body, { childList: true, subtree: true })
    this.measure()
    requestAnimationFrame(this.fit)
    document.fonts?.ready.then(this.fit)
    this.settle = setTimeout(this.fit, 500) // the first paint can be a pixel off
  }

  disconnect() {
    window.removeEventListener("resize", this.fit)
    this.observer?.disconnect()
    this.mutations?.disconnect()
    cancelAnimationFrame(this.raf)
    clearTimeout(this.settle)
  }

  measure() {
    const top = Math.round(this.element.getBoundingClientRect().top + window.scrollY)
    if (top !== this.top) document.documentElement.style.setProperty("--stage-top", `${top}px`) // only on a change: the watch loops otherwise
    this.top = top
    this.element.style.setProperty("--stage-below", `${this.belowValue}px`)
  }
}
