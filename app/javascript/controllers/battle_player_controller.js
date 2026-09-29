import { Controller } from "@hotwired/stimulus"
import { createTimeline } from "animejs"
import { Board } from "battle/board"
import { choreograph } from "battle/choreography"

// The event player (docs/HANDOFF.md §6).
//
// Each broadcast beat carries the resolver's events, the board before them
// and the board after them. Beats play one at a time: show `before`, turn
// the events into one anime.js timeline (gestures, damage numbers, HP
// changes as they happen), and swap in `after` only when the timeline
// completes, so the broadcast never spoils the outcome.
//
// Views never compute outcomes (§12): every number shown comes from an event,
// and the log text comes from the server. How each event plays is
// battle/choreography.js; the board it plays on is battle/board.js.
//
// Skip = timeline.complete(); GM fast-forward = timeline.speed. A reload
// or late join renders the current state server-side and never replays events.
const BACKLOG_SPEEDUP = 4
// How long to wait for a beat that's missing from the sequence before
// playing the ones after it anyway.
const GAP_WAIT = 1500
const REDUCED_MOTION_SPEED = 4
const FAST_SPEED = 2
const FAST_KEY = "polychrome.fastBattles"

export default class extends Controller {
  static targets = ["boardContainer", "stage", "fx", "log", "panel", "playback", "skip", "fast", "ticker"]
  static values = { panelUrl: String, next: Number, cries: Object, words: Object }

  connect() {
    this.queue = []
    this.current = null
    this.fast = this.readFast()
    this.board = new Board({ element: this.element, container: this.boardContainerTarget, stage: this.stageTarget, fx: this.fxTarget,
                             words: this.hasWordsValue ? this.wordsValue : {}, cries: this.criesValue })
    this.showFast()
    this.scrollLog()
  }

  // Each viewer's own choice, on top of the GM's pacing for everyone.
  toggleFast() {
    this.fast = !this.fast
    try { localStorage.setItem(FAST_KEY, this.fast ? "1" : "0") } catch {}
    this.showFast()
    if (this.current) this.current.timeline.speed = this.speed
  }

  readFast() {
    try { return localStorage.getItem(FAST_KEY) === "1" } catch { return false }
  }

  showFast() {
    if (!this.hasFastTarget) return
    this.fastTarget.setAttribute("aria-pressed", String(this.fast))
    this.fastTarget.classList.toggle("is-current", this.fast)
  }

  disconnect() {
    clearTimeout(this.reloadTimer)
    this.current?.timeline.pause()
    this.queue = []
    this.current = null
  }

  // Beats play in the order they happened, whatever order they arrive in.
  enqueue(event) {
    const beat = event.detail.beat
    if (beat.positionValue < this.nextValue) return beat.element.remove() // already shown on load
    this.queue.push(beat)
    this.queue.sort((a, b) => a.positionValue - b.positionValue)
    if (!this.current) this.playNext()
  }

  skip() {
    this.current?.timeline.complete()
  }

  // While a beat plays, the confirm and cancel keys skip it (the menu is
  // hidden until it ends, so they can't mean anything else).
  key(event) {
    if (!this.current || event.altKey || event.ctrlKey || event.metaKey) return
    if (event.target.closest?.("input, textarea, select, [contenteditable]")) return
    if (!["Enter", " ", "Escape", "z", "Z", "x", "X"].includes(event.key)) return
    event.preventDefault()
    this.skip()
  }

  // GM fast-forward arrives as a replaced #battle_playback element.
  playbackTargetConnected() {
    if (this.current) this.current.timeline.speed = this.speed
  }

  get speed() {
    const gm = Number(this.hasPlaybackTarget ? this.playbackTarget.dataset.speed : 1) || 1
    const backlog = this.queue.length >= 2 ? BACKLOG_SPEEDUP : 1
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches ? REDUCED_MOTION_SPEED : 1
    return gm * backlog * reduced * (this.fast ? FAST_SPEED : 1)
  }

  playNext() {
    clearTimeout(this.gapTimer)
    const head = this.queue[0]
    if (head && head.positionValue > this.nextValue && !this.waited) {
      // A beat before this one hasn't arrived yet: give it a moment.
      this.waited = true
      this.gapTimer = setTimeout(() => this.playNext(), GAP_WAIT)
      return
    }
    this.waited = false
    const beat = this.queue.shift()
    if (beat) this.nextValue = beat.positionValue + 1
    if (!beat) {
      this.current = null
      this.skipTarget.hidden = true
      // A panel still reloading keeps its "…" until the new one lands.
      if (this.hasPanelTarget && !this.reloading) this.panelTarget.classList.remove("is-resolving")
      return
    }

    const events = beat.eventsValue
    this.board.abilities = beat.abilitiesValue
    this.showBoard(beat.beforeTarget)
    this.fxTarget.replaceChildren()

    const lines = [...beat.logTarget.content.children]
    const timeline = createTimeline({ autoplay: false, onComplete: () => this.finish(beat, events) })
    let at = 0
    events.forEach((event, i) => {
      const line = lines[i]
      if (line && line.textContent.trim()) timeline.call(() => this.appendLog(line), at)
      at += choreograph(this.board, timeline, event, at)
    })
    timeline.call(() => {}, Math.max(at, 1))

    this.current = { beat, timeline }
    const busy = events.some((e) => e.type !== "command_accepted")
    this.skipTarget.hidden = !busy
    if (busy && this.hasPanelTarget) this.panelTarget.classList.add("is-resolving")
    timeline.speed = this.speed
    timeline.play()
  }

  finish(beat, events) {
    this.showBoard(beat.afterTarget)
    this.fxTarget.replaceChildren()
    beat.element.remove()
    this.refreshPanel(events)
    this.current = null
    this.playNext()
  }


  showBoard(template) {
    this.boardContainerTarget.replaceChildren(template.content.cloneNode(true))
  }

  appendLog(line) {
    this.logTarget.append(line.cloneNode(true))
    while (this.logTarget.children.length > 60) this.logTarget.firstElementChild.remove()
    this.scrollLog()
    // A phone may not show the stage: the last lines say what happened.
    if (this.hasTickerTarget) {
      this.tickerTarget.append(line.cloneNode(true))
      while (this.tickerTarget.children.length > 3) this.tickerTarget.firstElementChild.remove()
    }
  }

  scrollLog() {
    this.logTarget.parentElement.scrollTop = this.logTarget.parentElement.scrollHeight
  }

  // --- the per-seat command panel ---

  // After submitting, the panel shows a placeholder until the beat plays.
  // If that beat already finished before the response landed, reload now.
  panelLoaded(event) {
    if (!this.hasPanelTarget || event?.target !== this.panelTarget) return
    if (this.panelTarget.querySelector("[data-resolving]") && !this.current && !this.queue.length) {
      this.refreshPanel()
      return
    }
    this.settled()
    // The results let go of a phone's bottom edge: bring them into view.
    const over = this.panelTarget.querySelector(".command-panel--over")
    if (over && !this.shownOver && window.matchMedia("(max-width: 640px)").matches) {
      this.shownOver = true
      over.scrollIntoView({ block: "start" })
    }
  }

  // The panel matches the board again: show it.
  settled() {
    this.reloading = false
    clearTimeout(this.reloadTimer)
    if (!this.current) this.panelTarget.classList.remove("is-resolving")
  }

  // Reload the panel after a beat so it matches the new state. A beat that
  // only records someone else's command doesn't interrupt a player who is
  // mid-choice or typing.
  refreshPanel(events = []) {
    if (!this.hasPanelTarget) return // the shared screen has no commands
    const panel = this.panelTarget
    const onlyInputs = events.every((e) => e.type === "command_accepted")
    const busy = panel.querySelector("[data-choosing]") || panel.contains(document.activeElement)
    const placeholder = panel.querySelector("[data-resolving]")
    if (onlyInputs && busy && !placeholder) return this.settled()

    // Until the new panel arrives, the old one (last round's HP, "Waiting
    // for…") stays behind the "…". A load that never comes gives up.
    this.reloading = true
    clearTimeout(this.reloadTimer)
    this.reloadTimer = setTimeout(() => this.settled(), 4000)

    const url = new URL(this.panelUrlValue, window.location.href).href
    const current = panel.src ? new URL(panel.src, window.location.href).href : null
    if (current === url) panel.reload()
    else panel.src = url
  }
}
