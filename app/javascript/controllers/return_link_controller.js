import { Controller } from "@hotwired/stimulus"
import { takeReturn, forgetReturn } from "stage"

// After a battle, "Back to where you were": the page the stage pulled you
// away from (stage.js), if it did. Otherwise the link stays hidden and the
// panel's usual ways back are there.
export default class extends Controller {
  static targets = ["link"]

  connect() {
    const saved = takeReturn()
    if (!saved?.url) return
    // Already one of the usual ways back: that one leads, in the lead's place.
    const path = new URL(saved.url, window.location.href).pathname
    const same = [...this.element.querySelectorAll("a")].find((a) => a !== this.linkTarget && new URL(a.href, window.location.href).pathname === path)
    if (same) {
      same.classList.remove("button--quiet")
      same.classList.add("play")
      same.addEventListener("click", forgetReturn, { once: true })
      return
    }

    this.linkTarget.href = saved.url
    this.linkTarget.textContent = `Back to ${saved.title || "where you were"}`
    this.linkTarget.hidden = false
  }

  go() {
    forgetReturn()
  }
}
