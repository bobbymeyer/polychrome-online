import { Controller } from "@hotwired/stimulus"

// Rows added one at a time (the battle setup's monsters): "+" on the first
// row stamps the template as the next row, with its index written in; "−"
// on an added row takes it out. The form's own listeners (the forecast)
// hear the new fields as they're changed.
const CAP = 8

export default class extends Controller {
  static targets = ["body", "row", "template"]

  add() {
    if (this.rowTargets.length >= CAP) return
    const index = this.rowTargets.length
    const html = this.templateTarget.innerHTML.replaceAll("__i__", String(index)).replaceAll("__n__", String(index + 1))
    this.bodyTarget.insertAdjacentHTML("beforeend", html)
    this.rowTargets.at(-1).querySelector("select")?.focus()
    this.element.dispatchEvent(new Event("change", { bubbles: true }))
  }

  remove(event) {
    event.currentTarget.closest("tr").remove()
    // The rows left are numbered again, so the form posts 0, 1, 2… without a gap.
    this.rowTargets.forEach((row, i) => {
      row.querySelectorAll("select, input").forEach((field) => {
        field.name = field.name.replace(/\[encounter\]\[\d+\]/, `[encounter][${i}]`)
        field.setAttribute("aria-label", field.getAttribute("aria-label").replace(/Monster \d+/, `Monster ${i + 1}`))
      })
    })
    this.element.dispatchEvent(new Event("change", { bubbles: true }))
  }
}
