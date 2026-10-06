import { Controller } from "@hotwired/stimulus"

// Your own row in the party panel is marked here, on each render and after
// each refresh: first in the list, "You"
// on it (stage.css), from the seat the table says you have.
export default class extends Controller {
  connect() {
    this.mark()
    // A refresh by morphing puts the server's order back.
    this.onMorph = () => this.mark()
    document.addEventListener("turbo:morph", this.onMorph)
  }

  disconnect() {
    document.removeEventListener("turbo:morph", this.onMorph)
  }

  mark() {
    const id = this.element.closest(".table")?.dataset.seatCharacter
    const row = id && this.element.querySelector(`li[data-character="${CSS.escape(id)}"]`)
    if (!row) return
    row.classList.add("is-you")
    row.parentElement.prepend(row)
  }
}
