import { Controller } from "@hotwired/stimulus"
import { animate } from "animejs"
import { GESTURES } from "motion/gestures"
import { reducedMotion } from "screen"

// The dialogue box (docs/HANDOFF.md §7, §9.5): GM and NPC lines play here one
// at a time, typed out beside the speaker's portrait. Player lines go
// straight to the log. A dialogue line only appears in the log once the box
// has finished typing it (the log drawer keeps the newest line in view).
//
// A line too long for the box goes in pages, each typed out in turn: the box
// stays the speaker's height and never scrolls.
//
// Click the box to finish typing, or to move on to the next page or line.
// Waiting pages and lines also move on by themselves, so a busy GM doesn't
// strand anyone. The × puts the box away (what's left goes to the log) until
// the next line comes.
// Nothing here is shared: each viewer reads at their own pace.
//
// In battle (autoHide) the box only appears while someone is speaking, and
// leaves once everything said has been read.
const TYPE_MS = 22
const BATCH_MS = 60
const HOLD_MS = 1600
const HOLD_PER_CHAR_MS = 35

// How the portrait reacts to an expression, from the shared gestures (§3.2).
const EXPRESSION_GESTURES = { happy: "bounce", angry: "shake", surprised: "pop", worried: "float", sad: "float", determined: "bounce" }

export default class extends Controller {
  static targets = ["box", "portrait", "name", "text", "more", "live"]
  static values = { autoHide: Boolean }

  connect() {
    this.queue = []
    this.current = null
    this.speakerKey = null
    this.pages = []
    // The last line said, as the page came: in pages too, once the box has its size.
    if (this.hasBoxTarget && !this.boxTarget.hidden && this.textTarget.textContent.trim()) {
      requestAnimationFrame(() => {
        if (this.current || this.boxTarget.hidden) return
        this.pages = this.paginate(this.textTarget.textContent)
        this.textTarget.textContent = this.pages.shift()
        this.moreTarget.hidden = this.pages.length === 0
      })
    }
  }

  // While lines are being said, the page is "busy": a battle starting waits
  // for them (stage.js), so nobody is pulled away mid-scene.
  set busy(value) {
    if (value) document.documentElement.dataset.dialogueBusy = "true"
    else delete document.documentElement.dataset.dialogueBusy
  }

  disconnect() {
    this.busy = false
    clearTimeout(this.startTimer)
    clearTimeout(this.hideTimer)
    clearTimeout(this.pageTimer)
    this.stopTyping()
    clearTimeout(this.holdTimer)
  }

  arrive(event) {
    const line = event.detail.line
    // No box on this page (a local co-op controller: the screen has it), so
    // nothing holds the line back: it's readable in the log straight away.
    if (!line.dialogueValue || !this.hasBoxTarget) {
      line.element.classList.remove("is-pending")
      // The party moved on: what was last said was said somewhere else, so
      // the box puts it away (unless it's still typing something out).
      if (line.element.dataset.moved && this.hasBoxTarget && !this.current && this.queue.length === 0) this.boxTarget.hidden = true
      return
    }

    this.queue.push(line)
    this.queue.sort((a, b) => a.idValue - b.idValue)
    this.busy = true
    if (!this.current) {
      // Lines sent together can arrive in any order: let the batch land and
      // sort before starting.
      clearTimeout(this.startTimer)
      this.startTimer = setTimeout(() => this.current || this.next(), BATCH_MS)
      return
    }

    this.moreTarget.hidden = false
    // Mid-line (pages still to come), the next line waits for them.
    if (!this.typing && !this.pages.length) this.scheduleNext()
  }

  // A line that isn't a message: a boss's opening words (boss_intro).
  // It goes to the front of the queue and never to the log.
  say(event) {
    if (!this.hasBoxTarget) return
    const { speaker, text, plate, expression } = event.detail
    const line = {
      speakerValue: speaker, text, plate, expressionValue: expression || "",
      speakerKeyValue: `said:${speaker}`, portraitValue: "", dialogueValue: true,
      element: document.createElement("li")
    }
    this.queue.unshift(line)
    this.busy = true
    if (this.current && !this.typing) this.moreTarget.hidden = false
    if (!this.current) this.next()
  }

  // A line taken back while it's in the box leaves it at once.
  streamed(event) {
    const stream = event.target
    if (stream.getAttribute?.("action") !== "remove" || !this.current?.element) return
    if (stream.getAttribute("target") !== this.current.element.id) return

    this.stopTyping()
    clearTimeout(this.holdTimer)
    this.holdTimer = null
    this.clearPages()
    this.current = null
    if (this.queue.length) return this.next()
    this.textTarget.textContent = ""
    this.nameTarget.textContent = ""
    this.portraitTarget.replaceChildren()
    this.boxTarget.hidden = true // nothing left to show, at the table too
    this.busy = false
  }

  advance() {
    if (this.typing) return this.finishTyping()
    if (this.pages.length) return this.current ? this.nextPage() : this.showNextPage()
    if (this.queue.length) this.next()
  }

  // Put the box away. Whatever it still had to say is read in the log; the
  // next line brings it back.
  dismiss() {
    clearTimeout(this.startTimer)
    clearTimeout(this.holdTimer)
    clearTimeout(this.hideTimer)
    this.holdTimer = null
    this.stopTyping()
    this.onTyped = null
    this.clearPages()
    for (const line of [ this.current, ...this.queue ]) line?.element.classList.remove("is-pending")
    this.queue = []
    this.current = null
    this.boxTarget.hidden = true
    this.busy = false
  }

  // Escape works anywhere, even mid-sentence in the composer. Enter, Space and
  // Z work when you aren't typing or on a control.
  key(event) {
    if ((!this.current && !this.pages.length) || event.altKey || event.ctrlKey || event.metaKey) return
    if (event.key === "Escape") return this.advance()
    if (!["Enter", " ", "z", "Z"].includes(event.key)) return
    if (event.target.closest?.("input, textarea, select, button, a, [contenteditable]")) return
    event.preventDefault()
    this.advance()
  }

  next() {
    clearTimeout(this.holdTimer)
    this.holdTimer = null
    this.clearPages()
    let line = this.queue.shift()
    while (line && !line.element.isConnected) line = this.queue.shift() // taken back before its turn
    if (!line) {
      this.current = null
      this.busy = false
      return
    }

    this.current = line
    clearTimeout(this.hideTimer)
    this.boxTarget.hidden = false
    this.moreTarget.hidden = true
    this.nameTarget.textContent = line.speakerValue
    // The name tag wears the speaker's colour, as their plate does.
    this.nameTarget.style.cssText = this.plateOf(line)
    this.showPortrait(line)
    this.liveTarget.textContent = `${line.speakerValue}: ${line.text}`
    this.play(line.text, () => this.finished(line))
  }

  finished(line) {
    line.element.classList.remove("is-pending")
    if (this.queue.length) {
      this.moreTarget.hidden = false
      this.scheduleNext()
    } else {
      // The last line stays up long enough to be read, then the page is free.
      this.hideTimer = setTimeout(() => {
        if (this.queue.length) return
        if (this.autoHideValue) {
          this.boxTarget.hidden = true
          this.current = null
        }
        this.busy = false
      }, HOLD_MS + line.text.length * HOLD_PER_CHAR_MS)
    }
  }

  // Give the current line time to be read, then move on.
  scheduleNext() {
    if (this.holdTimer) return
    this.holdTimer = setTimeout(() => this.next(), HOLD_MS + this.current.text.length * HOLD_PER_CHAR_MS)
  }

  plateOf(line) {
    return line.plate || (line.hasPlateValue && line.plateValue) || ""
  }

  showPortrait(line) {
    const speakerChanged = line.speakerKeyValue !== this.speakerKey
    this.speakerKey = line.speakerKeyValue
    // Narration is a voice, not a face: no portrait, the words take the room.
    const narration = line.speakerKeyValue === "narrator"
    this.boxTarget.classList.toggle("is-narration", narration)
    if (narration) return this.portraitTarget.replaceChildren()

    let portrait
    if (line.portraitValue) {
      portrait = document.createElement("img")
      portrait.src = line.portraitValue
      portrait.alt = ""
      portrait.className = "speaker-portrait speaker-portrait--large"
    } else {
      portrait = document.createElement("span")
      portrait.className = "speaker-portrait speaker-portrait--large speaker-portrait--plate"
      portrait.textContent = line.speakerValue.charAt(0)
      portrait.style.cssText = this.plateOf(line)
    }
    this.portraitTarget.replaceChildren(portrait)

    if (reducedMotion()) return
    const name = speakerChanged ? "pop" : EXPRESSION_GESTURES[line.expressionValue]
    if (name) animate(portrait, GESTURES[name](1))
  }

  // --- pages ---

  // Type the words out a page at a time, then call done.
  play(text, done) {
    this.pages = this.paginate(text)
    this.onPagesDone = done
    this.nextPage()
  }

  nextPage() {
    clearTimeout(this.pageTimer)
    const page = this.pages.shift()
    this.moreTarget.hidden = true
    this.type(page, () => {
      if (this.pages.length) {
        this.moreTarget.hidden = false
        this.pageTimer = setTimeout(() => this.nextPage(), HOLD_MS + page.length * HOLD_PER_CHAR_MS)
      } else {
        const done = this.onPagesDone
        this.onPagesDone = null
        done?.()
      }
    })
  }

  // A page of the last line said, as the page came: shown, not typed.
  showNextPage() {
    this.textTarget.textContent = this.pages.shift()
    this.moreTarget.hidden = this.pages.length === 0
  }

  clearPages() {
    clearTimeout(this.pageTimer)
    this.pages = []
    this.onPagesDone = null
  }

  // Split the words into pages that each fit the body as it's sized now. A
  // body with no height of its own grows to fit, so it's always one page.
  paginate(text) {
    const body = this.textTarget
    body.textContent = text
    const room = body.clientHeight
    if (!room || body.scrollHeight <= room + 1) return [ text ]

    const words = text.split(/(?<=\s)/)
    const fits = (from, to) => {
      body.textContent = words.slice(from, to).join("").trim()
      return body.scrollHeight <= room + 1
    }
    const pages = []
    let start = 0
    while (start < words.length) {
      // The most words from here that fit (always at least one).
      let lo = start + 1, hi = words.length
      while (lo < hi) {
        const mid = Math.ceil((lo + hi) / 2)
        if (fits(start, mid)) lo = mid
        else hi = mid - 1
      }
      pages.push(words.slice(start, lo).join("").trim())
      start = lo
    }
    body.textContent = ""
    return pages
  }

  // --- typewriter ---

  type(text, done) {
    this.stopTyping()
    if (reducedMotion()) {
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

}
