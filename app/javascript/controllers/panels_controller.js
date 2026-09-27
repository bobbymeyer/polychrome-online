import { Controller } from "@hotwired/stimulus"

// Collapsible panels that stay as you left them (a town's services): which
// are open is remembered for this page in this tab, so paying at the inn
// comes back to the inn. A link into a panel (#shop) opens it too, and so
// does a building in the skyline.
export default class extends Controller {
  connect() {
    this.restore()
    this.onToggle = (event) => { if (event.target.tagName === "DETAILS" && event.target.id) this.save() }
    this.element.addEventListener("toggle", this.onToggle, true)
    // A refresh by morphing keeps this element but closes the panels.
    this.onMorph = () => this.restore()
    document.addEventListener("turbo:morph", this.onMorph)
    // A link to a panel (a building in the skyline) opens it and brings it into view.
    this.onHash = () => this.follow()
    window.addEventListener("hashchange", this.onHash)
  }

  disconnect() {
    this.element.removeEventListener("toggle", this.onToggle, true)
    document.removeEventListener("turbo:morph", this.onMorph)
    window.removeEventListener("hashchange", this.onHash)
  }

  // Something that stands for a panel (a building in the skyline) opens it.
  go(event) {
    event.preventDefault()
    this.follow(event.currentTarget.dataset.panel)
  }

  follow(id = decodeURIComponent(window.location.hash.slice(1))) {
    const panel = id && document.getElementById(id)?.closest("details")
    if (!panel || !this.element.contains(panel)) return
    panel.open = true
    panel.scrollIntoView({ block: "start", behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" })
  }

  get key() {
    return `polychrome.panels.${window.location.pathname}`
  }

  panels() {
    return [ ...this.element.querySelectorAll("details[id]") ]
  }

  restore() {
    let open = []
    try { open = JSON.parse(window.sessionStorage.getItem(this.key) || "[]") } catch { /* no storage */ }
    const hash = decodeURIComponent(window.location.hash.slice(1))
    const target = hash && document.getElementById(hash)
    if (target && this.element.contains(target)) open.push(target.closest("details")?.id)
    this.panels().forEach((panel) => { if (open.includes(panel.id)) panel.open = true })
  }

  save() {
    const open = this.panels().filter((panel) => panel.open).map((panel) => panel.id)
    try { window.sessionStorage.setItem(this.key, JSON.stringify(open)) } catch { /* no storage */ }
  }
}
