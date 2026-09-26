import { Controller } from "@hotwired/stimulus"
import { createTimeline } from "animejs"
import { gesture } from "battle/gestures"

// The event player (docs/HANDOFF.md §6).
//
// Each broadcast beat carries the resolver's events, the board before them
// and the board after them. Beats play one at a time: show `before`, turn
// the events into one anime.js timeline (gestures, damage numbers, HP
// changes as they happen), and swap in `after` only when the timeline
// completes, so the broadcast never spoils the outcome.
//
// Views never compute outcomes (§12): every number shown comes from an event,
// and the log text comes from the server.
//
// Skip = timeline.complete(); GM fast-forward = timeline.speed. A reload
// or late join renders the current state server-side and never replays events.
const BACKLOG_SPEEDUP = 4
const REDUCED_MOTION_SPEED = 4

export default class extends Controller {
  static targets = ["boardContainer", "stage", "fx", "log", "panel", "playback", "skip"]
  static values = { panelUrl: String }

  connect() {
    this.queue = []
    this.current = null
    this.scrollLog()
  }

  disconnect() {
    this.current?.timeline.pause()
    this.queue = []
    this.current = null
  }

  enqueue(event) {
    this.queue.push(event.detail.beat)
    if (!this.current) this.playNext()
  }

  skip() {
    this.current?.timeline.complete()
  }

  // GM fast-forward arrives as a replaced #battle_playback element.
  playbackTargetConnected() {
    if (this.current) this.current.timeline.speed = this.speed
  }

  get speed() {
    const gm = Number(this.hasPlaybackTarget ? this.playbackTarget.dataset.speed : 1) || 1
    const backlog = this.queue.length >= 2 ? BACKLOG_SPEEDUP : 1
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches ? REDUCED_MOTION_SPEED : 1
    return gm * backlog * reduced
  }

  playNext() {
    const beat = this.queue.shift()
    if (!beat) {
      this.current = null
      this.skipTarget.hidden = true
      this.panelTarget.classList.remove("is-resolving")
      return
    }

    const events = beat.eventsValue
    this.abilities = beat.abilitiesValue
    this.showBoard(beat.beforeTarget)
    this.fxTarget.replaceChildren()

    const lines = [...beat.logTarget.content.children]
    const timeline = createTimeline({ autoplay: false, onComplete: () => this.finish(beat, events) })
    let at = 0
    events.forEach((event, i) => {
      const line = lines[i]
      if (line && line.textContent.trim()) timeline.call(() => this.appendLog(line), at)
      at += this.stage(timeline, event, at)
    })
    timeline.call(() => {}, Math.max(at, 1))

    this.current = { beat, timeline }
    const busy = events.some((e) => e.type !== "command_accepted")
    this.skipTarget.hidden = !busy
    if (busy) this.panelTarget.classList.add("is-resolving")
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

  // --- one event -> timeline entries; returns the time it takes (ms) ---

  stage(tl, e, at) {
    switch (e.type) {
      case "round_start":
        this.banner(tl, `Round ${e.round}`, at)
        return 700
      case "turn_start":
        tl.call(() => this.setActive(e.unit), at)
        return 120
      case "turn_end":
        tl.call(() => this.setActive(null), at)
        return 60
      case "command_accepted":
        tl.call(() => this.setReady(e.actor, true), at)
        return 0
      case "attack":
        return gesture(tl, this.sprite(e.actor), "lunge", at, this.facing(e.actor))
      case "cast": {
        const ability = this.abilities[e.ability] || {}
        this.caption(tl, ability.name || e.ability, at)
        if (e.mp_cost) tl.call(() => this.addMp(e.actor, -e.mp_cost), at)
        return Math.max(gesture(tl, this.sprite(e.actor), ability.gesture || "flash", at, this.facing(e.actor)), 450)
      }
      case "damage":
        tl.call(() => this.setHp(e.target, e.hp), at)
        this.popup(tl, e.target, String(e.amount), e.status === "poison" ? "poison" : "damage", at)
        gesture(tl, this.sprite(e.target), e.status === "poison" ? "tint" : "shake", at)
        return 480
      case "heal":
        tl.call(() => this.setHp(e.target, e.hp), at)
        this.popup(tl, e.target, String(e.amount), "heal", at)
        gesture(tl, this.sprite(e.target), "float", at)
        return 480
      case "crit":
        this.popup(tl, e.target, "CRIT!", "crit", at)
        gesture(tl, this.stageTarget, "flash", at)
        return 260
      case "miss":
        this.popup(tl, e.target || e.actor, e.reason === "immune" ? "IMMUNE" : "MISS", "miss", at)
        return 380
      case "status_applied":
        tl.call(() => this.setStatus(e.target, e.status, true), at)
        this.popup(tl, e.target, this.humanize(e.status), "status", at)
        gesture(tl, this.sprite(e.target), "tint", at)
        return 450
      case "status_expired":
        tl.call(() => this.setStatus(e.target, e.status, false), at)
        return 250
      case "buff_applied":
        this.popup(tl, e.target, `${e.stat.toUpperCase()} ${e.amount > 0 ? "▲" : "▼"}`, e.amount > 0 ? "heal" : "status", at)
        return 380
      case "buff_expired":
        return 120
      case "ko":
        tl.call(() => this.setKo(e.target, true), at)
        return gesture(tl, this.sprite(e.target), "fade", at)
      case "revive":
        tl.call(() => { this.setKo(e.target, false); this.setHp(e.target, e.hp) }, at)
        return gesture(tl, this.sprite(e.target), "pop", at)
      case "defend":
        this.popup(tl, e.actor, "DEFEND", "miss", at)
        return gesture(tl, this.sprite(e.actor), "bounce", at)
      case "turn_skipped":
        this.popup(tl, e.unit, e.reason === "sleep" ? "Zzz" : e.reason === "paralyze" ? "…" : "?", "miss", at)
        return 420
      case "action_failed":
        this.popup(tl, e.actor, e.reason === "silenced" ? "SILENCED" : "NO MP", "miss", at)
        return 420
      case "flee":
        if (!e.success) {
          this.caption(tl, "Couldn't escape!", at)
          return 600
        }
        this.party().forEach((el) => gesture(tl, el, "slide", at, 1))
        this.banner(tl, "Escaped!", at)
        return 900
      case "timeout":
        if (e.defaulted.length) this.banner(tl, "Time's up!", at)
        return e.defaulted.length ? 700 : 0
      case "victory":
        this.banner(tl, "Victory!", at, "victory")
        return 1300
      case "defeat":
        this.banner(tl, "Defeat", at, "defeat")
        return 1300
      case "gm_override":
        // GM power is never hidden (§12): every override gets a banner.
        this.banner(tl, `GM: ${this.humanize(e.op)}`, at, "gm")
        if (e.hp !== undefined) tl.call(() => this.setHp(e.unit, e.hp), at)
        return 900
      default:
        return 0
    }
  }

  // --- board lookups and live DOM changes (all undone by the final swap) ---

  showBoard(template) {
    this.boardContainerTarget.replaceChildren(template.content.cloneNode(true))
  }

  unitEl(id) {
    return this.boardContainerTarget.querySelector(`[data-unit="${CSS.escape(id)}"]`)
  }

  rosterEl(id) {
    return this.boardContainerTarget.querySelector(`[data-roster="${CSS.escape(id)}"]`)
  }

  sprite(id) {
    return this.unitEl(id)?.querySelector("[data-sprite]")
  }

  party() {
    return [...this.boardContainerTarget.querySelectorAll(".unit--party [data-sprite]")]
  }

  // Party members face left (toward the enemies), enemies face right.
  facing(id) {
    return this.unitEl(id)?.classList.contains("unit--party") ? -1 : 1
  }

  setActive(id) {
    this.boardContainerTarget.querySelectorAll(".is-active").forEach((el) => el.classList.remove("is-active"))
    if (id) [this.unitEl(id), this.rosterEl(id)].forEach((el) => el?.classList.add("is-active"))
  }

  setReady(id, ready) {
    const marker = this.rosterEl(id)?.querySelector("[data-ready]")
    if (marker) marker.textContent = ready ? "▶" : ""
  }

  setHp(id, hp) {
    const row = this.rosterEl(id)
    if (!row) return // enemy HP is never shown on the shared board
    row.querySelector("[data-hp]").textContent = hp
    const pct = Math.round((100 * hp) / Number(row.dataset.maxHp))
    const bar = row.querySelector("[data-hp-bar]")
    bar.style.width = `${pct}%`
    bar.className = `bar__fill bar__fill--${pct === 0 ? "ko" : pct <= 25 ? "danger" : pct <= 50 ? "warn" : "ok"}`
  }

  addMp(id, delta) {
    const mp = this.rosterEl(id)?.querySelector("[data-mp]")
    if (mp) mp.textContent = Math.max(0, Number(mp.textContent) + delta)
  }

  setKo(id, ko) {
    ;[this.unitEl(id), this.rosterEl(id)].forEach((el) => el?.classList.toggle("is-ko", ko))
    if (ko) {
      this.setHp(id, 0)
      ;[this.unitEl(id), this.rosterEl(id)].forEach((el) => el?.querySelector("[data-badges]")?.replaceChildren())
    }
  }

  setStatus(id, status, on) {
    ;[this.unitEl(id), this.rosterEl(id)].forEach((el) => {
      const badges = el?.querySelector("[data-badges]")
      if (!badges) return
      const existing = badges.querySelector(`[data-status="${CSS.escape(status)}"]`)
      if (on && !existing) {
        const badge = document.createElement("li")
        badge.className = `badge badge--${status}`
        badge.dataset.status = status
        badge.textContent = this.humanize(status)
        badges.append(badge)
      } else if (!on) {
        existing?.remove()
      }
    })
  }

  appendLog(line) {
    this.logTarget.append(line.cloneNode(true))
    while (this.logTarget.children.length > 60) this.logTarget.firstElementChild.remove()
    this.scrollLog()
  }

  scrollLog() {
    this.logTarget.parentElement.scrollTop = this.logTarget.parentElement.scrollHeight
  }

  // --- transient effects in the fx layer (text nodes created and removed) ---

  popup(tl, id, text, kind, at) {
    const anchor = this.sprite(id)
    if (!anchor) return
    const stage = this.stageTarget.getBoundingClientRect()
    const box = anchor.getBoundingClientRect()
    const el = document.createElement("span")
    el.className = `popup popup--${kind}`
    el.textContent = text
    el.style.left = `${box.left - stage.left + box.width / 2}px`
    el.style.top = `${box.top - stage.top + box.height * 0.3}px`
    this.fxTarget.append(el)
    tl.add(el, { opacity: [0, 1, 1, 0], translateY: [0, -26, -30, -40], duration: 900, ease: "outQuad" }, at)
    tl.call(() => el.remove(), at + 900)
  }

  banner(tl, text, at, kind = "round") {
    const el = document.createElement("div")
    el.className = `banner banner--${kind}`
    el.textContent = text
    this.fxTarget.append(el)
    tl.add(el, { opacity: [0, 1, 1, 0], scale: [0.8, 1, 1, 1], duration: kind === "round" ? 700 : 1200, ease: "outQuad" }, at)
  }

  caption(tl, text, at) {
    const el = document.createElement("div")
    el.className = "caption window"
    el.textContent = text
    this.fxTarget.append(el)
    tl.add(el, { opacity: [0, 1, 1, 0], duration: 700, ease: "linear" }, at)
  }

  humanize(token) {
    const s = String(token).replaceAll("_", " ")
    return s.charAt(0).toUpperCase() + s.slice(1)
  }

  // --- the per-seat command panel ---

  // After submitting, the panel shows a placeholder until the beat plays.
  // If that beat already finished before the response landed, reload now.
  panelLoaded() {
    if (this.panelTarget.querySelector("[data-resolving]") && !this.current && !this.queue.length) {
      this.refreshPanel()
    }
  }

  // Reload the panel after a beat so it matches the new state. A beat that
  // only records someone else's command doesn't interrupt a player who is
  // mid-choice or typing.
  refreshPanel(events = []) {
    const panel = this.panelTarget
    panel.classList.remove("is-resolving")
    const onlyInputs = events.every((e) => e.type === "command_accepted")
    const busy = panel.querySelector("[data-choosing]") || panel.contains(document.activeElement)
    const placeholder = panel.querySelector("[data-resolving]")
    if (onlyInputs && busy && !placeholder) return

    const url = new URL(this.panelUrlValue, window.location.href).href
    const current = panel.src ? new URL(panel.src, window.location.href).href : null
    if (current === url) panel.reload()
    else panel.src = url
  }
}
