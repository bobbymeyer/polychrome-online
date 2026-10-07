import { Controller } from "@hotwired/stimulus"

// Submits its form as soon as a choice changes.
//
// A choice that needs another field filled first (data-autosubmit-needs on
// the select: {"value": "field name"}) waits for that field: picking "A
// place" shows the place select, and it's choosing the place that submits.
export default class extends Controller {
  submit(event) {
    const needs = event?.target?.dataset?.autosubmitNeeds
    if (needs) {
      const field = this.element.elements[JSON.parse(needs)[event.target.value]]
      if (field && !field.value) return
    }
    this.element.requestSubmit()
  }
}
