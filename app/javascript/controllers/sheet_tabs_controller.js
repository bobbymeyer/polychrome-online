import { Controller } from "@hotwired/stimulus"

// A character's sheet, one section at a time (characters/show): the links
// along the top are tabs, and only the section pressed is shown. The
// address's hash picks it (so #gear lands on Gear, and #equipment, a section
// inside it, does too), else the one last open on this sheet, else the first.
// Without JavaScript every section shows, one under another.
export default class extends Controller {
  static targets = ["tab", "panel"]
  static values = { key: String }

  connect() {
    this.element.classList.add("is-tabbed")
    this.onHash = () => this.showFromHash()
    window.addEventListener("hashchange", this.onHash)
    this.showFromHash()
  }

  disconnect() {
    window.removeEventListener("hashchange", this.onHash)
  }

  pick(event) {
    const key = event.currentTarget.dataset.key
    if (!this.keys().includes(key)) return

    event.preventDefault()
    history.replaceState(history.state, "", `#${key}`)
    this.show(key)
  }

  showFromHash() {
    const hash = location.hash.replace(/^#/, "")
    const keys = this.keys()
    // A panel's key, or a section inside one (#equipment is in Gear).
    const inside = hash && !keys.includes(hash) && this.element.querySelector(`#${CSS.escape(hash)}`)?.closest("[data-sheet-tabs-target=panel]")?.dataset.key
    const wanted = keys.includes(hash) ? hash : inside
    const remembered = this.remember()
    this.show(wanted || (keys.includes(remembered) ? remembered : keys[0]))
  }

  show(key) {
    this.panelTargets.forEach((panel) => panel.classList.toggle("is-shown", panel.dataset.key === key))
    this.tabTargets.forEach((tab) => {
      const on = tab.dataset.key === key
      tab.classList.toggle("is-current", on)
      if (on) tab.setAttribute("aria-current", "true")
      else tab.removeAttribute("aria-current")
    })
    this.remember(key)
  }

  keys() {
    return this.panelTargets.map((panel) => panel.dataset.key)
  }

  remember(key) {
    try {
      if (key) sessionStorage.setItem(this.keyValue, key)
      return sessionStorage.getItem(this.keyValue)
    } catch {
      return null
    }
  }
}
