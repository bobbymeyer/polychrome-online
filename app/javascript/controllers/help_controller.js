import { Controller } from "@hotwired/stimulus"

// One line under a panel says what the control under the pointer or focus does
// (docs/DESIGN.md, "Help lines"): any control inside with data-help fills it
// while the pointer or focus is on it; otherwise the line says what it was
// rendered with (the panel's own word, or nothing). The battle's command menu
// has its own line (menu_controller).
export default class extends Controller {
  static targets = ["line"]

  connect() {
    this.standing = this.hasLineTarget ? this.lineTarget.textContent : ""
    this.onIn = (e) => this.show(e.target.closest?.("[data-help]"))
    this.onOut = (e) => this.show(e.relatedTarget?.closest?.("[data-help]"))
    this.element.addEventListener("mouseover", this.onIn)
    this.element.addEventListener("mouseout", this.onOut)
    this.element.addEventListener("focusin", this.onIn)
    this.element.addEventListener("focusout", this.onOut)
  }

  disconnect() {
    this.element.removeEventListener("mouseover", this.onIn)
    this.element.removeEventListener("mouseout", this.onOut)
    this.element.removeEventListener("focusin", this.onIn)
    this.element.removeEventListener("focusout", this.onOut)
  }

  show(control) {
    if (!this.hasLineTarget) return
    const help = control && this.element.contains(control) && control.dataset.help
    this.lineTarget.textContent = help || this.standing
  }
}
