import { Controller } from "@hotwired/stimulus"

// "/" or Ctrl/Cmd+K takes you to a world's book search from anywhere in its books, unless you are typing.
export default class extends Controller {
  static targets = ["input"]

  key(event) {
    const typing = event.target.closest("input, textarea, select, [contenteditable]")
    const asked = (event.key === "/" && !typing) || (event.key.toLowerCase() === "k" && (event.metaKey || event.ctrlKey))
    if (!asked || !this.hasInputTarget) return

    event.preventDefault()
    this.inputTarget.focus()
    this.inputTarget.select()
  }
}
