import { Controller } from "@hotwired/stimulus"

// GM editing on the pointcrawl map (docs/HANDOFF.md §7). Click empty ground
// to add a place, click a place or path to open it in the side panel, drag a
// place to move it. The SVG is replaced by a broadcast after every change,
// so everything here is delegated from the controller's element.
const DRAG_THRESHOLD = 4

export default class extends Controller {
  static values = { newUrl: String }

  connect() {
    this.onDown = this.down.bind(this)
    this.onMove = this.move.bind(this)
    this.onUp = this.up.bind(this)
    this.element.addEventListener("pointerdown", this.onDown)
    this.element.addEventListener("keydown", this.key.bind(this))
  }

  disconnect() {
    this.element.removeEventListener("pointerdown", this.onDown)
    window.removeEventListener("pointermove", this.onMove)
    window.removeEventListener("pointerup", this.onUp)
  }

  down(event) {
    const svg = event.target.closest("svg.map")
    if (!svg || event.button !== 0) return

    const node = event.target.closest("[data-map-node]")
    const edge = event.target.closest("[data-map-edge]")
    this.press = { svg, node, edge, start: this.point(svg, event), moved: false }
    if (node) {
      event.preventDefault()
      window.addEventListener("pointermove", this.onMove)
    }
    window.addEventListener("pointerup", this.onUp, { once: true })
  }

  move(event) {
    const { svg, node, start } = this.press
    const at = this.point(svg, event)
    if (!this.press.moved && Math.hypot(at.x - start.x, at.y - start.y) < DRAG_THRESHOLD) return

    this.press.moved = true
    this.press.at = this.clamp(at, svg)
    node.setAttribute("transform", `translate(${this.press.at.x} ${this.press.at.y})`)
    node.classList.add("is-dragging")
  }

  up(event) {
    window.removeEventListener("pointermove", this.onMove)
    const press = this.press
    this.press = null
    if (!press) return

    if (press.node && press.moved) return this.savePosition(press.node, press.at)
    if (press.node) return this.open(press.node.dataset.editUrl)
    if (press.edge) return this.open(press.edge.dataset.editUrl)
    if (event.target.closest("[data-map-ground]")) {
      const at = this.clamp(this.point(press.svg, event), press.svg)
      this.open(`${this.newUrlValue}?x=${at.x}&y=${at.y}`)
    }
  }

  key(event) {
    const node = event.target.closest?.("[data-map-node], [data-map-edge]")
    if (node && (event.key === "Enter" || event.key === " ")) {
      event.preventDefault()
      this.open(node.dataset.editUrl)
    }
  }

  open(url) {
    const panel = document.getElementById("map_panel")
    if (panel) panel.src = url
  }

  async savePosition(node, at) {
    const token = document.querySelector("meta[name=csrf-token]")?.content
    const response = await fetch(node.dataset.updateUrl, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": token },
      body: JSON.stringify({ map_node: { x: at.x, y: at.y } })
    })
    if (!response.ok) node.classList.add("is-error")
    // The broadcast re-renders the map with the saved position.
  }

  // Client coordinates -> the map's SVG coordinates.
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
