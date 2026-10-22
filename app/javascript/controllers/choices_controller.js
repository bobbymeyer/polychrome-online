import { Controller } from "@hotwired/stimulus"

// A form's selects list what a world's books hold, and an entry made in another tab isn't there until the form is
// loaded again. This fetches the page afresh and takes its options into the selects here, keeping what is chosen
// and everything typed. A select is matched by its field name with the row numbers taken out, so rows added since
// the page loaded get the options too.
export default class extends Controller {
  static targets = ["status"]

  async refresh() {
    this.say("Looking…")
    const response = await fetch(window.location.href, { headers: { Accept: "text/html" } })
    const fresh = new DOMParser().parseFromString(await response.text(), "text/html")
    const options = new Map()
    for (const select of fresh.querySelectorAll("form select[name]")) {
      const key = this.key(select)
      if (!options.has(key)) options.set(key, select.innerHTML)
    }

    let updated = 0
    for (const select of this.element.closest("form")?.querySelectorAll("select[name]") || []) {
      const html = options.get(this.key(select))
      if (html === undefined) continue

      const chosen = select.value
      select.innerHTML = html
      select.value = chosen
      updated += 1
    }
    this.say(updated ? "Choices refreshed." : "Nothing to refresh on this page: save the entry, then edit it.")
  }

  key(select) {
    return select.name.replace(/\[\d+\]/g, "[]")
  }

  say(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}
