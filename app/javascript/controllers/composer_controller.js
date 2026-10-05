import { Controller } from "@hotwired/stimulus"

// The talk box (campaigns/composers/show). Enter sends, Shift+Enter starts
// a new line. The GM's speaker is a row of chips (the Narrator, whoever is on
// the stage, whoever they last spoke as); a whisper comes from the party
// panel (composer:whisper, with the character) and shows who hears it. When
// the stage's scene moves on, an empty box fetches itself again so the chips
// follow the beat. A player's chips say who hears: everyone, or the GM.
export default class extends Controller {
  static targets = ["body", "speaker", "whisperTo", "chip", "whispering", "whisperName"]

  key(event) {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing || event.target !== this.bodyTarget) return

    event.preventDefault()
    if (this.bodyTarget.value.trim()) this.element.requestSubmit()
  }

  pick(event) {
    if (!this.hasSpeakerTarget) return
    this.speakerTarget.value = event.currentTarget.dataset.speaker
    this.press(event.currentTarget)
    this.bodyTarget.focus()
  }

  pickTo(event) {
    this.whisperToTarget.value = event.currentTarget.dataset.whisper
    this.press(event.currentTarget)
    this.bodyTarget.focus()
  }

  // From the party panel: whisper to this character.
  whisper(event) {
    if (!this.hasWhisperingTarget) return
    const { id, name } = event.detail
    this.whisperToTarget.value = id
    this.whisperNameTarget.textContent = name
    this.whisperingTarget.hidden = false
    this.element.scrollIntoView({ block: "nearest" })
    this.bodyTarget.focus()
  }

  aloud() {
    this.whisperToTarget.value = ""
    this.whisperingTarget.hidden = true
    this.bodyTarget.focus()
  }

  // The stage's scene changed: with nothing typed, fetch the box again for the speaker it has now.
  staged(event) {
    if (event.detail?.newStream?.target !== "table_scene") return
    if (this.bodyTarget.value.trim()) return
    const frame = this.element.closest("turbo-frame")
    if (frame?.src) setTimeout(() => frame.reload(), 50)
  }

  press(chip) {
    this.chipTargets.forEach((c) => c.setAttribute("aria-pressed", String(c === chip)))
  }
}
