import { Controller } from "@hotwired/stimulus"

// A choice laid out as a table (docs/DESIGN.md, "Players steer"): one option
// a row, tight and even. The whole row is the control: a click anywhere on it
// presses the row's button (the first one shown: a player's pick, the GM's
// settle or go), Up and Down move between rows, and Enter on a focused row
// presses it as a button does. Hover and focus light the row (stage.css).
export default class extends Controller {
  connect() {
    this.onClick = (event) => {
      const row = event.target.closest(".pick-row")
      if (!row || !this.element.contains(row)) return
      if (event.target.closest("button, a, input, select, label")) return // the control itself took it
      this.act(row)?.click()
    }
    this.onKey = (event) => {
      const step = { ArrowDown: 1, ArrowUp: -1 }[event.key]
      if (!step || event.altKey || event.ctrlKey || event.metaKey) return
      const row = event.target.closest(".pick-row")
      if (!row) return
      const rows = this.rows
      const next = rows[(rows.indexOf(row) + step + rows.length) % rows.length]
      const act = next && this.act(next)
      if (!act) return
      event.preventDefault()
      act.focus()
    }
    this.element.addEventListener("click", this.onClick)
    this.element.addEventListener("keydown", this.onKey)
  }

  disconnect() {
    this.element.removeEventListener("click", this.onClick)
    this.element.removeEventListener("keydown", this.onKey)
  }

  get rows() {
    return [...this.element.querySelectorAll(".pick-row")]
  }

  // The row's button for this seat: the first one that's shown and can be pressed.
  act(row) {
    return [...row.querySelectorAll(".pick-row__act")].find((b) => b.offsetParent !== null && !b.disabled)
  }
}
