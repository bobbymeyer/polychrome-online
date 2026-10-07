import { Controller } from "@hotwired/stimulus"

// A grid form's "Add a row" (effects, a script's rules, drops): one more
// blank row like the last, its fields named for the next index, so a six-
// rule script is one save, not three.
export default class extends Controller {
  static targets = ["body"]

  add() {
    const rows = [...this.bodyTarget.rows]
    const row = rows[rows.length - 1].cloneNode(true)
    const index = rows.length
    row.querySelectorAll("input, select, textarea").forEach((field) => {
      if (field.name) field.name = field.name.replace(/\[(\d+)\]/, `[${index}]`)
      const label = field.getAttribute("aria-label")
      if (label) field.setAttribute("aria-label", label.replace(/\d+$/, String(index + 1)))
      if (field.type === "checkbox") field.checked = false
      else if (field.tagName === "SELECT") field.selectedIndex = 0
      else if (field.type !== "hidden") field.value = ""
    })
    this.bodyTarget.append(row)
    row.querySelector("input:not([type=hidden]), select")?.focus()
  }
}
