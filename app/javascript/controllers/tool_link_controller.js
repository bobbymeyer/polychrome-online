import { Controller } from "@hotwired/stimulus"

// A button outside the GM's tools that opens one of them (the Now line's
// "Call a check", "Play a scene"): it says which, and gm_tools_controller does it.
export default class extends Controller {
  static values = { key: String }

  open() {
    window.dispatchEvent(new CustomEvent("gm-tools:open", { detail: { key: this.keyValue } }))
  }
}
