import { Controller } from "@hotwired/stimulus"

// "Whisper" beside a party member (campaigns/tables/_party, the GM's): tells
// the talk box who hears the next line (composer#whisper). On a phone the
// box is on the Stage view: the strip is switched there too.
export default class extends Controller {
  start(event) {
    const { characterId, characterName } = event.currentTarget.dataset
    window.dispatchEvent(new CustomEvent("composer:whisper", { detail: { id: characterId, name: characterName } }))
    const table = this.element.closest(".table")
    const views = table && this.application.getControllerForElementAndIdentifier(table, "table-views")
    views?.show("stage")
  }
}
