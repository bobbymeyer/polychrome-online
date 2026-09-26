import { Controller } from "@hotwired/stimulus"

// One line in the table log (app/views/messages/_message.html.erb). A line
// that arrives live announces itself; the dialogue controller decides what
// to do with it. Lines rendered with the page just sit in the log.
export default class extends Controller {
  static targets = ["body"]
  static values = { id: Number, live: Boolean, dialogue: Boolean, speaker: String, speakerKey: String, expression: String, portrait: String }

  // Moving the element (placeInOrder) makes Stimulus reconnect it, so a
  // line announces itself only the first time.
  connect() {
    if (!this.liveValue || this.element.dataset.arrived) return

    this.element.dataset.arrived = "true"
    this.placeInOrder()
    this.dispatch("arrived", { detail: { line: this } })
  }

  // Lines created together (e.g. a journey and its encounter) can be
  // broadcast out of order; the log is always in message order.
  placeInOrder() {
    const later = [...this.element.parentElement.children].find(
      (sibling) => sibling !== this.element && Number(sibling.dataset.chatLineIdValue) > this.idValue
    )
    if (later && this.element.nextElementSibling !== later) later.before(this.element)
  }

  get text() {
    return this.hasBodyTarget ? this.bodyTarget.innerText.trim() : ""
  }
}
