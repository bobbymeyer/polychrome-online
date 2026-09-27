import { Controller } from "@hotwired/stimulus"

// One broadcast beat (app/views/battles/_beat.html.erb). It only announces
// itself; the battle-player on the page queues and plays it.
export default class extends Controller {
  static targets = ["before", "after", "log"]
  static values = { events: Array, abilities: Object, position: Number }

  connect() {
    this.dispatch("arrived", { detail: { beat: this } })
  }
}
