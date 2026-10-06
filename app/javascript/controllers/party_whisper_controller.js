import { Controller } from "@hotwired/stimulus"

// "Whisper" beside a party member (campaigns/tables/_party, the GM's): tells
// the talk box who hears the next line (composer#whisper). On a phone the
// box is on the Stage view: the strip is asked for it too (table-views:show).
export default class extends Controller {
  start(event) {
    const { characterId, characterName } = event.currentTarget.dataset
    window.dispatchEvent(new CustomEvent("composer:whisper", { detail: { id: characterId, name: characterName } }))
    window.dispatchEvent(new CustomEvent("table-views:show", { detail: { key: "stage" } }))
  }
}
