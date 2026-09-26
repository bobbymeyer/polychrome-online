import { Controller } from "@hotwired/stimulus"

// One line in the table log (app/views/messages/_message.html.erb). A line
// that arrives live announces itself; the dialogue controller decides what
// to do with it. Lines rendered with the page just sit in the log.
export default class extends Controller {
  static targets = ["body"]
  static values = { live: Boolean, dialogue: Boolean, speaker: String, speakerKey: String, expression: String, portrait: String }

  connect() {
    if (this.liveValue) this.dispatch("arrived", { detail: { line: this } })
  }

  get text() {
    return this.hasBodyTarget ? this.bodyTarget.innerText.trim() : ""
  }
}
