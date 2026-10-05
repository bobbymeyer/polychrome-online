import { Controller } from "@hotwired/stimulus"

// The party panel is replaced live for everyone alike (Campaign::Broadcasts),
// so your own row is marked here, on each render: first in the list, "You"
// on it (stage.css), from the seat the table says you have.
export default class extends Controller {
  connect() {
    const id = this.element.closest(".table")?.dataset.seatCharacter
    const row = id && this.element.querySelector(`li[data-character="${CSS.escape(id)}"]`)
    if (!row) return
    row.classList.add("is-you")
    row.parentElement.prepend(row)
  }
}
