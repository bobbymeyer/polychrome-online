import { Controller } from "@hotwired/stimulus"

// The monster form reads itself back as it is typed. Each reading is posted to the server, which answers with a
// Turbo Stream drawn from an unsaved entry (Bestiary::BehaviorPreviewsController: the rules and phases in the
// page's own words; StrengthPreviewsController: the entry tried against a party and set among its neighbours).
// Whichever fields a reading doesn't depend on (the prose, the art, the drops) don't set it going.
export default class extends Controller {
  static values = { readingUrl: String, strengthUrl: String }

  connect() {
    this.timers = {}
    this.requests = {}
  }

  disconnect() {
    Object.values(this.timers).forEach(clearTimeout)
    Object.values(this.requests).forEach((request) => request.abort())
  }

  changed(event) {
    const name = event.type === "rows:added" ? "monster[ai_script]" : event.target.name || ""
    if (/^monster\[(ai_script|phases)\]/.test(name)) this.schedule("reading", this.readingUrlValue, /^monster\[(ai_script|phases)\]/, 250)
    if (/^monster\[(name|level|base_type|second_type|boss|undead|giant|stats|affinities|status_immune|ai_script|phases)\b/.test(name)) {
      this.schedule("strength", this.strengthUrlValue, /^monster\[(name|level|base_type|second_type|boss|undead|giant|stats|affinities|status_immune|ai_script|phases)\b/, 800)
    }
  }

  schedule(kind, url, fields, delay) {
    clearTimeout(this.timers[kind])
    this.timers[kind] = setTimeout(() => this.refresh(kind, url, fields), delay)
  }

  async refresh(kind, url, fields) {
    const body = new FormData()
    for (const [key, value] of new FormData(this.element)) {
      if (fields.test(key)) body.append(key, value)
    }

    this.requests[kind]?.abort()
    this.requests[kind] = new AbortController()
    try {
      const response = await fetch(url, {
        method: "POST", body, signal: this.requests[kind].signal,
        headers: { Accept: "text/vnd.turbo-stream.html", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content }
      })
      if (response.ok) window.Turbo.renderStreamMessage(await response.text())
    } catch (error) {
      if (error.name !== "AbortError") throw error
    }
  }
}
