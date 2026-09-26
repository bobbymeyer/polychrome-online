import { Controller } from "@hotwired/stimulus"
import { animate } from "animejs"
import { GESTURES } from "motion/gestures"

// The dialogue box (docs/HANDOFF.md §7, §9.5): GM and NPC lines play here one
// at a time, typed out beside the speaker's portrait. Player lines go
// straight to the log. A dialogue line only appears in the log once the box
// has finished typing it.
//
// Click the box to finish typing, or to move on to the next line. Waiting
// lines also move on by themselves, so a busy GM doesn't strand anyone.
// Nothing here is shared: each viewer reads at their own pace.
const TYPE_MS = 22
const BATCH_MS = 60
const HOLD_MS = 1600
const HOLD_PER_CHAR_MS = 35

// How the portrait reacts to an expression, from the shared gestures (§3.2).
const EXPRESSION_GESTURES = { happy: "bounce", angry: "shake", surprised: "pop", worried: "float", sad: "float", determined: "bounce" }

export default class extends Controller {
  static targets = ["box", "portrait", "name", "text", "more", "log", "live"]

  connect() {
    this.queue = []
    this.current = null
    this.speakerKey = null
    this.scrollLog()
  }

  disconnect() {
    clearTimeout(this.startTimer)
    this.stopTyping()
    clearTimeout(this.holdTimer)
  }

  arrive(event) {
    const line = event.detail.line
    if (!line.dialogueValue) return this.scrollLog()

    this.queue.push(line)
    this.queue.sort((a, b) => a.idValue - b.idValue)
    if (!this.current) {
      // Lines sent together can arrive in any order: let the batch land and
      // sort before starting.
      clearTimeout(this.startTimer)
      this.startTimer = setTimeout(() => this.current || this.next(), BATCH_MS)
      return
    }

    this.moreTarget.hidden = false
    if (!this.typing) this.scheduleNext()
  }

  advance() {
    if (this.typing) return this.finishTyping()
    if (this.queue.length) this.next()
  }

  // Escape works anywhere, even mid-sentence in the composer. Enter, Space and
  // Z work when you aren't typing or on a control.
  key(event) {
    if (!this.current || event.altKey || event.ctrlKey || event.metaKey) return
    if (event.key === "Escape") return this.advance()
    if (!["Enter", " ", "z", "Z"].includes(event.key)) return
    if (event.target.closest?.("input, textarea, select, button, a, [contenteditable]")) return
    event.preventDefault()
    this.advance()
  }

  next() {
    clearTimeout(this.holdTimer)
    this.holdTimer = null
    const line = this.queue.shift()
    if (!line) {
      this.current = null
      return
    }

    this.current = line
    this.boxTarget.hidden = false
    this.moreTarget.hidden = true
    this.nameTarget.textContent = line.speakerValue
    this.showPortrait(line)
    this.liveTarget.textContent = `${line.speakerValue}: ${line.text}`
    this.type(line.text, () => this.finished(line))
  }

  finished(line) {
    line.element.classList.remove("is-pending")
    this.scrollLog()
    if (this.queue.length) {
      this.moreTarget.hidden = false
      this.scheduleNext()
    }
  }

  // Give the current line time to be read, then move on.
  scheduleNext() {
    if (this.holdTimer) return
    this.holdTimer = setTimeout(() => this.next(), HOLD_MS + this.current.text.length * HOLD_PER_CHAR_MS)
  }

  showPortrait(line) {
    const speakerChanged = line.speakerKeyValue !== this.speakerKey
    this.speakerKey = line.speakerKeyValue

    let portrait
    if (line.portraitValue) {
      portrait = document.createElement("img")
      portrait.src = line.portraitValue
      portrait.alt = ""
      portrait.className = "speaker-portrait speaker-portrait--large"
    } else {
      portrait = document.createElement("span")
      portrait.className = `speaker-portrait speaker-portrait--large speaker-portrait--plate${line.speakerKeyValue === "narrator" ? " speaker-portrait--narrator" : ""}`
      portrait.textContent = line.speakerValue.charAt(0)
    }
    this.portraitTarget.replaceChildren(portrait)

    if (this.reducedMotion) return
    const name = speakerChanged ? "pop" : EXPRESSION_GESTURES[line.expressionValue]
    if (name) animate(portrait, GESTURES[name](1))
  }

  // --- typewriter ---

  type(text, done) {
    this.stopTyping()
    if (this.reducedMotion) {
      this.textTarget.textContent = text
      return done()
    }

    let shown = 0
    this.textTarget.textContent = ""
    this.onTyped = done
    this.typing = setInterval(() => {
      shown += 1
      this.textTarget.textContent = text.slice(0, shown)
      if (shown >= text.length) this.finishTyping()
    }, TYPE_MS)
    this.fullText = text
  }

  finishTyping() {
    this.stopTyping()
    this.textTarget.textContent = this.fullText
    const done = this.onTyped
    this.onTyped = null
    done?.()
  }

  stopTyping() {
    clearInterval(this.typing)
    this.typing = null
  }

  get reducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches
  }

  scrollLog() {
    const scroller = this.logTarget.parentElement
    scroller.scrollTop = scroller.scrollHeight
  }
}
