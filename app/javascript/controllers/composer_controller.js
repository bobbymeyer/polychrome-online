import { Controller } from "@hotwired/stimulus"

// The talk box (campaigns/composers/show). Enter sends, Shift+Enter starts
// a new line. The GM's speaker is a row of chips (the Narrator, whoever is on
// the stage, whoever they last spoke as); a whisper comes from the party
// panel (composer:whisper, with the character) and shows who hears it. When
// the stage's scene moves on, an empty box fetches itself again so the chips
// follow the beat. A player's chips say who hears: everyone, or the GM.
export default class extends Controller {
  static targets = ["body", "speaker", "whisperTo", "chip", "whispering", "whisperName"]

  connect() {
    this.beat = this.stagedBeat
  }

  // Which beat is on the stage (campaigns/tables/_scene), if any.
  get stagedBeat() {
    return document.getElementById("table_scene")?.dataset.beat || ""
  }

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

  // The table refreshed (turbo:morph) and the stage's scene moved on: with nothing typed, fetch the
  // box again for the speaker it has now. From its home (data-home): after a line is sent the
  // frame's src is the URL it was posted to, which can't be fetched.
  staged() {
    if (this.stagedBeat === this.beat) return
    this.beat = this.stagedBeat
    if (this.bodyTarget.value.trim()) return
    const frame = this.element.closest("turbo-frame")
    const home = frame?.dataset.home
    if (!home) return
    setTimeout(() => {
      const at = (url) => new URL(url, window.location.href).href
      if (frame.src && at(frame.src) === at(home)) frame.reload()
      else frame.src = home
    }, 50)
  }

  press(chip) {
    this.chipTargets.forEach((c) => c.setAttribute("aria-pressed", String(c === chip)))
  }
}
