import { Controller } from "@hotwired/stimulus"

// Editing a dungeon's floorplan (locations/_floorplan, locations/_dungeon),
// for the GM on the dungeon's page: drag a room to move it, click a room to
// open its panel beside the plan (where its ways are joined and cut), click
// a way to open the panel of the room it leaves from. The page refreshes
// after every change, so everything here is delegated from the element.
//
// A sibling of map_editor_controller, not a fork of it: a dungeon has no
// bends to drag, no waypoints, and no empty ground to click -- its rooms
// come from the generator and the add-a-room form, never from the plan.
const DRAG_THRESHOLD = 4

export default class extends Controller {
  connect() {
    this.onDown = this.down.bind(this)
    this.onMove = this.move.bind(this)
    this.onUp = this.up.bind(this)
    this.onKey = this.key.bind(this)
    this.element.addEventListener("pointerdown", this.onDown)
    this.element.addEventListener("keydown", this.onKey)
  }

  disconnect() {
    this.element.removeEventListener("pointerdown", this.onDown)
    this.element.removeEventListener("keydown", this.onKey)
    window.removeEventListener("pointermove", this.onMove)
    window.removeEventListener("pointerup", this.onUp)
  }

  down(event) {
    const svg = event.target.closest("svg.floorplan")
    if (!svg || event.button !== 0) return

    const room = event.target.closest("[data-floorplan-room]")
    const way = event.target.closest("[data-floorplan-path]")
    this.press = { svg, room, way, start: this.point(svg, event), moved: false }
    if (room) {
      event.preventDefault()
      window.addEventListener("pointermove", this.onMove)
    }
    window.addEventListener("pointerup", this.onUp, { once: true })
  }

  move(event) {
    const { svg, room, start } = this.press
    const at = this.point(svg, event)
    if (!this.press.moved && Math.hypot(at.x - start.x, at.y - start.y) < DRAG_THRESHOLD) return

    this.press.moved = true
    this.press.at = this.clamp(at, svg)
    room.setAttribute("transform", `translate(${this.press.at.x} ${this.press.at.y})`)
    room.classList.add("is-dragging")
  }

  up(event) {
    window.removeEventListener("pointermove", this.onMove)
    const press = this.press
    this.press = null
    if (!press) return

    if (press.room && press.moved) return this.savePosition(press.room, press.at)
    if (press.room) return this.open(press.room.dataset.updateUrl)
    // A way is cut from the panel of the room it leaves, so that is what it opens.
    if (press.way && event.target.closest(".floorplan__path-hit")) return this.openWay(press.way)
  }

  key(event) {
    const room = event.target.closest?.("[data-floorplan-room]")
    if (room && (event.key === "Enter" || event.key === " ")) {
      event.preventDefault()
      this.open(room.dataset.updateUrl)
    }
  }

  // The room a way leaves from, named on the way itself. Not matched out of
  // its key: "room-1" is a substring of "path-room-10-room-2".
  openWay(way) {
    const from = this.element.querySelector(`[data-floorplan-room="${way.dataset.floorplanFrom}"]`)
    if (from) this.open(from.dataset.updateUrl)
  }

  open(url) {
    const panel = document.getElementById("room_panel")
    if (panel) panel.src = url
    else window.Turbo.visit(url)
  }

  async savePosition(room, at) {
    const ok = await this.patch(room.dataset.updateUrl, { room: { x: at.x, y: at.y } })
    if (!ok) room.classList.add("is-error")
    // The page refreshes with the saved position.
  }

  async patch(url, body) {
    const token = document.querySelector("meta[name=csrf-token]")?.content
    const response = await fetch(url, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": token },
      body: JSON.stringify(body)
    })
    return response.ok
  }

  // Client coordinates -> the floorplan's SVG coordinates.
  point(svg, event) {
    const p = svg.createSVGPoint()
    p.x = event.clientX
    p.y = event.clientY
    const local = p.matrixTransform(svg.getScreenCTM().inverse())
    return { x: Math.round(local.x), y: Math.round(local.y) }
  }

  clamp(at, svg) {
    const box = svg.viewBox.baseVal
    return { x: Math.min(Math.max(at.x, 0), box.width), y: Math.min(Math.max(at.y, 0), box.height) }
  }
}
