import { Controller } from "@hotwired/stimulus"
import { get, set } from "storage"

// A <details> that stays as it was left through its panel's reloads (each
// command, each round reloads the GM's panel): filling in a form mid-fight
// isn't a race against the next beat.
export default class extends Controller {
  static values = { key: String }

  connect() {
    const was = get(this.keyValue, { session: true })
    if (was != null) this.element.open = was === "1"
    this.onToggle = () => set(this.keyValue, this.element.open ? "1" : "0", { session: true })
    this.element.addEventListener("toggle", this.onToggle)
  }

  disconnect() {
    this.element.removeEventListener("toggle", this.onToggle)
  }
}
