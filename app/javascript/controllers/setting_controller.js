import { Controller } from "@hotwired/stimulus"
import { setting, setSetting } from "storage"
import { reducedMotion } from "screen"

// A setting for this device in the account menu (Fast animations, Timing
// meter): a button that is on or off, kept in this browser under its key
// (storage.js) and pressed (aria-pressed) to match. Whoever acts on the
// setting reads the same key with storage's `setting`, and hears a change as
// it's made: setting:changed on window, detail { key, on }.
//
//   data-setting-key-value      the storage key
//   data-setting-default-value  before it's ever set: "on", "off" (the default) or
//                               "motion", on unless the viewer asked for reduced motion
export default class extends Controller {
  static values = { key: String, default: { type: String, default: "off" } }

  connect() {
    this.show(this.on)
  }

  toggle() {
    const on = !this.on
    setSetting(this.keyValue, on)
    this.show(on)
    window.dispatchEvent(new CustomEvent("setting:changed", { detail: { key: this.keyValue, on } }))
  }

  get on() {
    const fallback = this.defaultValue === "motion" ? !reducedMotion() : this.defaultValue === "on"
    return setting(this.keyValue, fallback)
  }

  show(on) {
    this.element.setAttribute("aria-pressed", String(on))
    this.element.classList.toggle("is-current", on)
  }
}
