import { Controller } from "@hotwired/stimulus"

// The GM asking from the map (maps/_sheet at the table, the GM's): pressing a
// place opens a small card by it, "Far Hold · 3 parts of a day", with Go (the
// party travels there, road by road) and Ask the table (a vote between here
// and there); the card's page link is the place's page. Esc, a press
// elsewhere or Close puts it away.
//
// The sheet is refreshed with the table (Campaign::Broadcasts), so a card
// that's open is remembered across a refresh and opened again where it was:
// on a new sheet when it's connected, on the same one when it's morphed.
let opened = null // { nodeId, x, y } while a card is open on this page

export default class extends Controller {
  static targets = ["card", "name", "journey", "go", "ask", "page", "noRoad", "goForm", "askForm"]

  connect() {
    this.onKey = (e) => { if (e.key === "Escape") this.close() }
    this.onDown = (e) => { if (!this.cardTarget.hidden && !this.cardTarget.contains(e.target) && !e.target.closest(".map-node__ask")) this.close() }
    this.onMorph = () => this.reopen()
    document.addEventListener("keydown", this.onKey)
    document.addEventListener("pointerdown", this.onDown)
    document.addEventListener("turbo:morph", this.onMorph)
    this.reopen()
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKey)
    document.removeEventListener("pointerdown", this.onDown)
    document.removeEventListener("turbo:morph", this.onMorph)
  }

  reopen() {
    if (!opened) return
    const link = this.element.querySelector(`.map-node__ask[data-node-id="${CSS.escape(opened.nodeId)}"]`)
    if (link) this.show(link, opened.x, opened.y, { focus: false })
    else opened = null
  }

  open(event) {
    event.preventDefault()
    // Beside the press, inside the sheet.
    const sheet = this.element.getBoundingClientRect()
    const x = Math.min(Math.max(event.clientX - sheet.left + 12, 8), sheet.width - 240)
    const y = Math.min(Math.max(event.clientY - sheet.top + 12, 8), sheet.height - 140)
    this.show(event.currentTarget, x, y)
  }

  show(link, x, y, { focus = true } = {}) {
    const { nodeId, nodeName, wayLabel, journey, warn, page } = link.dataset
    this.nameTarget.textContent = nodeName
    this.journeyTarget.textContent = journey || ""
    const reachable = Boolean(wayLabel)
    this.goTarget.hidden = !reachable
    this.askTarget.hidden = !reachable
    this.noRoadTarget.hidden = reachable
    this.goForm("to", nodeId)
    this.askForm("places[]", nodeId)
    this.goFormTarget.dataset.turboConfirm = warn ? `${warn} Go now?` : ""
    if (!warn) delete this.goFormTarget.dataset.turboConfirm
    this.pageTarget.hidden = !page
    if (page) this.pageTarget.href = page

    this.cardTarget.style.left = `${x}px`
    this.cardTarget.style.top = `${y}px`
    this.cardTarget.hidden = false
    opened = { nodeId, x, y }
    if (focus) this.cardTarget.querySelector("button:not([hidden])")?.focus({ preventScroll: true })
  }

  close() {
    this.cardTarget.hidden = true
    opened = null
  }

  goForm(name, value) { this.goFormTarget.querySelector(`input[name="${name}"]`).value = value }
  askForm(name, value) { this.askFormTarget.querySelector(`input[name="${name}"]`).value = value }
}
