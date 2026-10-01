import { Controller } from "@hotwired/stimulus"

// "Previously on…" (app/views/tables/_recap): opens by itself when this
// device hasn't been at the table for a while and the recap is of a session
// that's over, or when the link is pressed. While the table (or one of its
// battles) is open, this device keeps saying it's here.
const BREAK_MS = 3 * 60 * 60 * 1000
const HEARTBEAT_MS = 60 * 1000

export default class extends Controller {
  static targets = ["dialog"]
  static values = { campaign: Number, auto: Boolean, asked: Boolean }

  connect() {
    const last = this.lastSeen
    const controller = document.body.dataset.view === "controller" // the shared screen shows it
    // Asked for from the menu ("Previously on…": ?recap=1), or by itself after a break.
    if (this.hasDialogTarget && (this.askedValue || (this.autoValue && !controller && (last === null || Date.now() - last > BREAK_MS)))) {
      // After the dialogue box has had its moment.
      this.timer = setTimeout(() => this.open(), 400)
    }
    this.here()
    this.heartbeat = setInterval(() => this.here(), HEARTBEAT_MS)
  }

  disconnect() {
    clearTimeout(this.timer)
    clearInterval(this.heartbeat)
    this.here()
  }

  open() {
    if (!this.hasDialogTarget || this.dialogTarget.open) return
    this.dialogTarget.showModal()
  }

  get key() {
    return `polychrome.seen.${this.campaignValue}`
  }

  get lastSeen() {
    try {
      const value = window.localStorage.getItem(this.key)
      return value === null ? null : Number(value)
    } catch { return Date.now() } // no storage: never open by itself
  }

  here() {
    try { window.localStorage.setItem(this.key, String(Date.now())) } catch { /* no storage: the link still works */ }
  }
}
