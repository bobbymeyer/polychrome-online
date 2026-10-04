import { Controller } from "@hotwired/stimulus"

// Editing on a map's sheet (maps/_sheet; docs/HANDOFF.md §7 "Maps"), for the
// GM on a campaign's maps and a world's editors on its atlas. Click empty
// ground to add a place there, click a place or a road to open it (in the
// panel beside the map, else on its own page), drag a place or a map to
// move it, click a road to bend it where clicked, drag a bend, double-click
// a bend to take it out. The page is refreshed after every change, so
// everything here is delegated from the controller's element.
const DRAG_THRESHOLD = 4

export default class extends Controller {
  static values = { newUrl: String }

  connect() {
    this.onDown = this.down.bind(this)
    this.onMove = this.move.bind(this)
    this.onUp = this.up.bind(this)
    this.onDouble = this.double.bind(this)
    this.element.addEventListener("pointerdown", this.onDown)
    this.element.addEventListener("dblclick", this.onDouble)
    this.element.addEventListener("keydown", this.key.bind(this))
  }

  disconnect() {
    this.element.removeEventListener("pointerdown", this.onDown)
    this.element.removeEventListener("dblclick", this.onDouble)
    window.removeEventListener("pointermove", this.onMove)
    window.removeEventListener("pointerup", this.onUp)
  }

  down(event) {
    const svg = event.target.closest("svg.map")
    if (!svg || event.button !== 0) return

    const bend = event.target.closest("[data-map-bend]")
    const node = event.target.closest("[data-map-node], [data-map-child]")
    const edge = event.target.closest("[data-map-edge]")
    this.press = { svg, node, edge, bend, start: this.point(svg, event), moved: false }
    if (node || bend) {
      event.preventDefault()
      window.addEventListener("pointermove", this.onMove)
    }
    window.addEventListener("pointerup", this.onUp, { once: true })
  }

  move(event) {
    const { svg, node, bend, start } = this.press
    const at = this.point(svg, event)
    if (!this.press.moved && Math.hypot(at.x - start.x, at.y - start.y) < DRAG_THRESHOLD) return

    this.press.moved = true
    this.press.at = this.clamp(at, svg)
    if (bend) {
      bend.setAttribute("cx", this.press.at.x)
      bend.setAttribute("cy", this.press.at.y)
      bend.classList.add("is-dragging")
    } else {
      node.setAttribute("transform", `translate(${this.press.at.x} ${this.press.at.y})`)
      node.classList.add("is-dragging")
    }
  }

  up(event) {
    window.removeEventListener("pointermove", this.onMove)
    const press = this.press
    this.press = null
    if (!press) return

    if (press.bend && press.moved) return this.saveBend(press.edge, press.bend, press.at)
    if (press.bend) return
    if (press.node && press.moved) return this.savePosition(press.node, press.at)
    if (press.node) return this.open(press.node.dataset.editUrl)
    if (press.edge && event.target.closest(".map-edge__hit")) {
      const at = this.clamp(this.point(press.svg, event), press.svg)
      return this.addBend(press.edge, at)
    }
    if (press.edge) return this.open(press.edge.dataset.editUrl)
    if (event.target.closest("[data-map-ground], .map__picture")) {
      const at = this.clamp(this.point(press.svg, event), press.svg)
      const joint = this.newUrlValue.includes("?") ? "&" : "?"
      this.open(`${this.newUrlValue}${joint}x=${at.x}&y=${at.y}`)
    }
  }

  // A double-click on a bend takes it out of the road.
  double(event) {
    const bend = event.target.closest("[data-map-bend]")
    const edge = event.target.closest("[data-map-edge]")
    if (!bend || !edge) return

    event.preventDefault()
    const points = this.bendsOf(edge).filter((_, i) => i !== Number(bend.dataset.mapBend))
    this.saveRoad(edge, points)
  }

  key(event) {
    const node = event.target.closest?.("[data-map-node], [data-map-edge], [data-map-child]")
    if (node && (event.key === "Enter" || event.key === " ")) {
      event.preventDefault()
      this.open(node.dataset.editUrl)
    }
  }

  // The panel beside the map, when the page has one; else the page itself.
  open(url) {
    const panel = document.getElementById("map_panel")
    if (panel) panel.src = url
    else window.Turbo.visit(url)
  }

  bendsOf(edge) {
    return [...edge.querySelectorAll("[data-map-bend]")].map((c) => [Number(c.getAttribute("cx")), Number(c.getAttribute("cy"))])
  }

  async savePosition(node, at) {
    const key = node.dataset.mapNode !== undefined ? this.paramFor(node.dataset.updateUrl, "place") : this.paramFor(node.dataset.updateUrl, "map")
    const ok = await this.patch(node.dataset.updateUrl, { [key]: { x: at.x, y: at.y } })
    if (!ok) node.classList.add("is-error")
    // The page refreshes with the saved position.
  }

  saveBend(edge, bend, at) {
    const points = this.bendsOf(edge)
    points[Number(bend.dataset.mapBend)] = [at.x, at.y]
    return this.saveRoad(edge, points)
  }

  saveRoad(edge, points) {
    return this.patch(edge.dataset.updateUrl, { [this.paramFor(edge.dataset.updateUrl, "road")]: { waypoints: points } })
  }

  addBend(edge, at) {
    return this.patch(edge.dataset.updateUrl, { bend: { x: at.x, y: at.y } })
  }

  // The parameter a URL's record is written under: the campaign's nodes, edges and maps,
  // or the world's places, routes and maps.
  paramFor(url, what) {
    const world = url.includes("/worlds/")
    if (what === "place") return world ? "world_place" : "map_node"
    if (what === "road") return world ? "world_route" : "map_edge"
    return world ? "world_map" : "map"
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
