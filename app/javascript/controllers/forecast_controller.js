import { Controller } from "@hotwired/stimulus"

// Asks how the fight on this form is likely to go (ForecastsController)
// whenever who fights or what they face changes.
export default class extends Controller {
  static targets = ["frame"]
  static values = { url: String }

  connect() {
    this.refresh()
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  changed() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.refresh(), 300)
  }

  refresh() {
    const data = new FormData(this.element)
    const query = new URLSearchParams()
    for (const [key, value] of data) {
      if (/\[(characters|encounter)\]/.test(key)) query.append(key, value)
    }
    this.frameTarget.src = `${this.urlValue}?${query}`
  }
}
