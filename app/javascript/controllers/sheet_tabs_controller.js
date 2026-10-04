import { Controller } from "@hotwired/stimulus"

// A character's sheet, one section at a time (characters/show): the links
// along the top are tabs, and only the section pressed is shown. The
// address's hash picks it (so #equipment still lands on Equipment, and a
// link to it works), else the one last open on this sheet, else the first.
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
    const wanted = location.hash.replace(/^#/, "")
    const remembered = this.remember()
    const keys = this.keys()
    this.show(keys.includes(wanted) ? wanted : keys.includes(remembered) ? remembered : keys[0])
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
