import { Controller } from "@hotwired/stimulus"
import { getJSON, set, remove } from "storage"

// What is typed into an entry's form is kept in this browser as it is typed, so a closed tab or a dropped
// connection doesn't take a long entry with it. Nothing is put back on its own: coming back to the page offers the
// draft, and the person says yes or no. A save that goes through clears it.
export default class extends Controller {
  static values = { key: String }

  connect() {
    this.form = this.element.querySelector("form.book-form")
    if (!this.form) return

    this.initial = JSON.stringify(this.fields())
    const draft = getJSON(this.storageKey, null)
    if (draft && JSON.stringify(draft.fields) !== this.initial) this.offer(draft)
  }

  disconnect() {
    clearTimeout(this.timer)
    this.notice?.remove()
  }

  save() {
    if (!this.form) return
    clearTimeout(this.timer)
    this.timer = setTimeout(() => {
      const fields = this.fields()
      if (JSON.stringify(fields) === this.initial) remove(this.storageKey)
      else set(this.storageKey, JSON.stringify({ fields, savedAt: Date.now() }))
    }, 800)
  }

  submitted(event) {
    if (event.detail.success) {
      clearTimeout(this.timer)
      remove(this.storageKey)
    }
  }

  get storageKey() {
    return `draft:${this.keyValue}`
  }

  // [[name, value], ...] for everything a person typed, in the form's own order (files and the form's tokens aside).
  fields() {
    const skip = new Set(["authenticity_token", "_method", "utf8"])
    return [...new FormData(this.form)].filter(([name, value]) => !skip.has(name) && typeof value === "string")
  }

  offer(draft) {
    const notice = document.createElement("p")
    notice.className = "draft-notice"
    const when = new Date(draft.savedAt).toLocaleString()
    notice.append(`Changes from ${when} were kept in this browser and never saved. `)
    for (const [label, action] of [["Put them back", () => this.restore(draft)], ["Throw them away", () => this.discard()]]) {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "button button--quiet"
      button.textContent = label
      button.addEventListener("click", action)
      notice.append(button)
    }
    this.notice = notice
    this.form.before(notice)
  }

  discard() {
    remove(this.storageKey)
    this.notice?.remove()
  }

  restore(draft) {
    this.growRows(draft.fields)
    const touched = []
    const byName = new Map()
    for (const [name, value] of draft.fields) byName.set(name, [...(byName.get(name) || []), value])

    for (const [name, values] of byName) {
      const elements = [...this.form.elements].filter((element) => element.name === name)
      const queue = [...values]
      for (const element of elements) {
        if (element.type === "checkbox" || element.type === "radio") {
          element.checked = values.includes(element.value)
        } else if (element.type !== "file" && element.tagName !== "BUTTON" && element.type !== "submit") {
          if (queue.length) element.value = queue.shift()
        }
        touched.push(element)
      }
    }
    // Whatever reads the form as it changes (the live readings) hears of it.
    for (const element of touched) {
      element.dispatchEvent(new Event("input", { bubbles: true }))
      element.dispatchEvent(new Event("change", { bubbles: true }))
    }
    this.notice?.remove()
  }

  // A form with add-a-row tables (rows_controller) may have more rows in the draft than the page began with.
  growRows(fields) {
    for (const table of this.form.querySelectorAll("[data-controller~='rows']")) {
      const sample = table.querySelector("tbody [name]")?.name
      if (!sample) continue

      const prefix = sample.replace(/\[\d+\].*$/, "[")
      const indexes = fields.map(([name]) => name).filter((name) => name.startsWith(prefix)).map((name) => parseInt(name.slice(prefix.length), 10))
      const wanted = indexes.length ? Math.max(...indexes) + 1 : 0
      const add = table.querySelector("[data-action~='rows#add']")
      while (add && table.querySelector("tbody").rows.length < wanted) add.click()
    }
  }
}
