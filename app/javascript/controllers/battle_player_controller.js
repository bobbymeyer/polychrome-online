import { Controller } from "@hotwired/stimulus"
import { createTimeline } from "animejs"
import { gesture } from "motion/gestures"
import { play } from "sound"

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
// How long to wait for a beat that's missing from the sequence before
// playing the ones after it anyway.
const GAP_WAIT = 1500
const REDUCED_MOTION_SPEED = 4
const FAST_SPEED = 2
const FAST_KEY = "polychrome.fastBattles"

export default class extends Controller {
  static targets = ["boardContainer", "stage", "fx", "log", "panel", "playback", "skip", "fast"]
  static values = { panelUrl: String, next: Number, cries: Object }

  connect() {
    this.queue = []
    this.current = null
    this.fast = this.readFast()
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
      if (this.hasPanelTarget) this.panelTarget.classList.remove("is-resolving")
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

  // --- one event -> timeline entries; returns the time it takes (ms) ---

  stage(tl, e, at) {
    switch (e.type) {
      case "round_start":
        this.banner(tl, `Round ${e.round}`, at)
        return 400
      case "turn_start":
        tl.call(() => this.setActive(e.unit), at)
        return 120
      case "turn_end":
        tl.call(() => this.setActive(null), at)
        return 60
      case "command_accepted":
        tl.call(() => this.setReady(e.actor, true), at)
        return 0
      case "jump":
        // Up and out of the frame, and out of reach, until its next turn.
        tl.add(this.sprite(e.actor), { translateY: [0, -220], opacity: [1, 0], duration: 420, ease: "inQuad" }, at)
        this.caption(tl, "Jump!", at, "skill")
        return 500
      case "land":
        tl.add(this.sprite(e.actor), { translateY: [-220, 0], opacity: [0, 1], duration: 260, ease: "inExpo" }, at)
        if (e.target) gesture(tl, this.stageTarget, "shake", at + 240)
        return 320
      case "covered":
        this.popup(tl, e.unit, "COVER!", "status", at)
        gesture(tl, this.sprite(e.unit), "lunge", at, this.facing(e.unit))
        return 380
      case "counter":
        this.die(tl, e.actor, e, at)
        this.popup(tl, e.actor, "COUNTER!", "crit", at)
        return 300
      case "second_wind":
        tl.call(() => { this.setKo(e.target, false); this.setHp(e.target, e.hp) }, at)
        this.popup(tl, e.target, "SECOND WIND!", "perfect", at)
        gesture(tl, this.sprite(e.target), "bounce", at)
        return 700
      case "mp_restored":
        tl.call(() => this.addMp(e.target, e.amount), at)
        this.popup(tl, e.target, `+${e.amount} MP`, "status", at)
        return 250
      case "custom_action":
        // A player's own idea, in their words.
        this.caption(tl, `“${e.text}”`, at, "custom")
        return Math.max(gesture(tl, this.sprite(e.actor), "bounce", at), 700)
      case "custom_roll":
        this.die(tl, e.actor, e, at)
        this.banner(tl, e.success ? "It works!" : "No luck", at + 150, "gm")
        if (e.line) this.caption(tl, e.line, at + 500, "narration")
        return e.line ? 1400 : 900
      case "custom_unruled":
        this.caption(tl, "No ruling: attacks instead", at)
        return 500
      case "desperation":
        return this.cutIn(tl, e, at)
      case "unit_joined":
        // The board after the beat has them; here, the entrance.
        this.banner(tl, e.guest ? `${e.name} joins the party!` : `${e.name} appears!`, at, "gm")
        return 900
      case "unit_left":
        gesture(tl, this.sprite(e.unit), "fade", at)
        this.banner(tl, `${e.name} leaves`, at, "gm")
        return 900
      case "attack":
        if (e.perfect) this.popup(tl, e.actor, "PERFECT!", "perfect", at)
        return gesture(tl, this.sprite(e.actor), "lunge", at, this.facing(e.actor))
      case "item_used":
        this.caption(tl, e.name || e.item, at, "item")
        return Math.max(gesture(tl, this.sprite(e.actor), "bounce", at), 450)
      case "cast": {
        const ability = this.abilities[e.ability] || {}
        this.caption(tl, ability.name || e.ability, at, ability.kind)
        if (e.perfect) this.popup(tl, e.actor, "PERFECT!", "perfect", at)
        if (e.mp_cost) tl.call(() => this.addMp(e.actor, -e.mp_cost), at)
        return Math.max(gesture(tl, this.sprite(e.actor), ability.gesture || "flash", at, this.facing(e.actor)), 450)
      }
      case "damage":
        tl.call(() => this.setHp(e.target, e.hp), at)
        this.popup(tl, e.target, String(e.amount), e.status === "poison" ? "poison" : "damage", at)
        gesture(tl, this.sprite(e.target), e.status === "poison" ? "tint" : "shake", at)
        // The type chart, said out loud.
        if (e.effectiveness > 100) {
          this.popup(tl, e.target, "SUPER EFFECTIVE!", "weak", at + 120)
          gesture(tl, this.stageTarget, "flash", at + 120)
          return 560
        }
        if (e.effectiveness < 100) {
          this.popup(tl, e.target, "NOT VERY EFFECTIVE", "resist", at + 120)
          return 520
        }
        return 380
      case "heal":
        tl.call(() => this.setHp(e.target, e.hp), at)
        this.popup(tl, e.target, String(e.amount), "heal", at)
        gesture(tl, this.sprite(e.target), "float", at)
        return 380
      case "crit":
        this.die(tl, e.actor, e, at)
        this.popup(tl, e.target, "CRIT!", "crit", at)
        gesture(tl, this.stageTarget, "flash", at)
        return 260
      case "miss":
        this.die(tl, e.reason === "resisted" ? e.target : e.actor, e, at)
        this.popup(tl, e.target || e.actor, { immune: e.damage_type ? "NO EFFECT" : "IMMUNE", nothing_to_cure: "NO EFFECT", nothing_to_steal: "NOTHING", steal_failed: "MISSED" }[e.reason] || "MISS", "miss", at)
        return 380
      case "status_applied":
        this.die(tl, e.target, e, at)
        tl.call(() => this.setStatus(e.target, e.status, true), at)
        this.popup(tl, e.target, this.humanize(e.status), "status", at, `status-${e.status}`)
        gesture(tl, this.sprite(e.target), "tint", at)
        return 450
      case "status_expired":
        tl.call(() => this.setStatus(e.target, e.status, false), at)
        if (e.reason === "cured") {
          this.popup(tl, e.target, `${this.humanize(e.status)} cured`, "status", at, `status-${e.status}`)
          return 380
        }
        return 250
      case "buff_applied":
        this.popup(tl, e.target, `${e.stat.toUpperCase()} ${e.amount > 0 ? "up" : "down"}`, "status", at)
        return 380
      case "buff_expired":
        return 120
      case "ko":
        tl.call(() => this.setKo(e.target, true), at)
        return gesture(tl, this.sprite(e.target), "fade", at)
      case "revive":
        tl.call(() => { this.setKo(e.target, false); this.setHp(e.target, e.hp) }, at)
        return gesture(tl, this.sprite(e.target), "pop", at)
      case "steal":
        this.die(tl, e.actor, e, at)
        this.popup(tl, e.target, `Stole ${e.name}!`, "status", at)
        gesture(tl, this.sprite(e.actor), "lunge", at, this.facing(e.actor))
        return 600
      case "scan":
        this.popup(tl, e.target, "Scanned", "status", at)
        return 450
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
        this.die(tl, e.actor, e, at)
        if (!e.success) {
          this.caption(tl, "Couldn't escape!", at)
          return 600
        }
        this.party().forEach((el) => gesture(tl, el, "slide", at, 1))
        this.banner(tl, "Escaped!", at, "escape")
        return 900
      case "timeout":
        if (e.defaulted.length) this.banner(tl, "Time's up!", at)
        return e.defaulted.length ? 700 : 0
      case "victory":
        this.banner(tl, "Victory!", at, "victory")
        tl.call(() => play("victory"), at)
        // The party's victory hop, as in the games.
        this.party().forEach((el, i) => { gesture(tl, el, "bounce", at + 200 + i * 80); gesture(tl, el, "bounce", at + 700 + i * 80) })
        // A boss gets its epitaph: the victory says what it beat.
        if (this.element.dataset.bossDown) {
          this.banner(tl, this.element.dataset.bossDown, at + 1300, "boss-down")
          return 2800
        }
        return 1500
      case "defeat":
        this.banner(tl, "Defeat", at, "defeat")
        tl.call(() => play("defeat"), at)
        return 1300
      case "gm_override":
        // GM power is never hidden (§12): every override is in the log, and
        // gets a banner, except the routine auto for absent players.
        if (e.op === "auto") return 0
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
    this.rosterEl(id)?.querySelector("[data-ready]")?.classList.toggle("is-ready", ready)
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

  // A d100 beside a unit, for the rolls that decide something: a crit, a
  // miss, a status, a steal, a getaway. Green when it came in.
  die(tl, id, e, at) {
    if (!e.roll) return
    const cameIn = e.roll <= e.needed
    this.popup(tl, id, String(e.roll), "die", at, cameIn ? "is-in" : "is-out")
  }

  popup(tl, id, text, kind, at, extra = "") {
    const anchor = this.sprite(id)
    if (!anchor) return
    const stage = this.stageTarget.getBoundingClientRect()
    const box = anchor.getBoundingClientRect()
    const el = document.createElement("span")
    el.className = `popup popup--${kind} ${extra}`.trim()
    el.textContent = text
    el.style.left = `${box.left - stage.left + box.width / 2}px`
    el.style.top = `${box.top - stage.top + box.height * 0.3}px`
    // Numbers land at a slight tilt, never the same twice (decoration, not outcome).
    if (["damage", "heal", "poison"].includes(kind)) el.style.rotate = `${(Math.random() * 12 - 6).toFixed(1)}deg`
    this.fxTarget.append(el)
    tl.add(el, { opacity: [0, 1, 1, 0], translateY: [8, -30, -34, -44], scale: [1.6, 1, 1, 0.9], duration: 900, ease: "outQuad" }, at)
    tl.call(() => el.remove(), at + 900)
  }

  banner(tl, text, at, kind = "round") {
    const el = document.createElement("div")
    el.className = `banner banner--${kind}`
    el.textContent = text
    this.fxTarget.append(el)
    if (["victory", "defeat", "escape", "boss-down"].includes(kind)) {
      // Thrown across the stage from the left, held, then gone.
      tl.add(el, { opacity: [0, 1, 1, 1, 0], translateX: ["-60%", "0%", "0%", "0%", "4%"], duration: 1300, ease: "outExpo" }, at)
    } else {
      tl.add(el, { opacity: [0, 1, 1, 0], translateX: [-24, 0, 0, 8], duration: kind === "round" ? 400 : 1200, ease: "outQuad" }, at)
    }
  }

  // A desperation move: the stage stops for the character. A slab in their
  // colour cuts across it, with their sprite, their line and the move.
  cutIn(tl, e, at) {
    const sprite = this.sprite(e.actor)
    const el = document.createElement("div")
    el.className = "cut-in"
    const plate = sprite?.querySelector(".sprite__plate")
    if (plate) el.style.cssText = plate.getAttribute("style") || ""

    const figure = document.createElement("div")
    figure.className = "cut-in__figure"
    if (sprite) figure.append(sprite.cloneNode(true))
    const words = document.createElement("div")
    words.className = "cut-in__words"
    const cry = this.criesValue[e.actor]
    if (cry) {
      const line = document.createElement("p")
      line.className = "cut-in__cry"
      line.textContent = cry
      words.append(line)
    }
    const move = document.createElement("p")
    move.className = "cut-in__move"
    move.textContent = e.name
    words.append(move)
    el.append(figure, words)
    this.fxTarget.append(el)

    const hold = cry ? 1500 + Math.min(cry.length * 18, 900) : 1100
    tl.call(() => play("desperation"), at)
    tl.add(el, { opacity: [0, 1, 1, 0], translateX: ["-40%", "0%", "0%", "30%"], duration: hold, ease: "outExpo" }, at)
    tl.add(figure, { translateX: [-60, 0], scale: [1.4, 1], duration: 380, ease: "outBack" }, at + 80)
    tl.call(() => el.remove(), at + hold)
    return hold
  }

  caption(tl, text, at, kind = null) {
    const el = document.createElement("div")
    el.className = `caption window${kind ? ` caption--${kind}` : ""}`
    el.textContent = text
    this.fxTarget.append(el)
    tl.add(el, { opacity: [0, 1, 1, 0], translateX: [-32, 0, 0, 0], duration: 700, ease: "outQuad" }, at)
  }

  humanize(token) {
    const s = String(token).replaceAll("_", " ")
    return s.charAt(0).toUpperCase() + s.slice(1)
  }

  // --- the per-seat command panel ---

  // After submitting, the panel shows a placeholder until the beat plays.
  // If that beat already finished before the response landed, reload now.
  panelLoaded() {
    if (!this.hasPanelTarget) return
    if (this.panelTarget.querySelector("[data-resolving]") && !this.current && !this.queue.length) {
      this.refreshPanel()
    }
  }

  // Reload the panel after a beat so it matches the new state. A beat that
  // only records someone else's command doesn't interrupt a player who is
  // mid-choice or typing.
  refreshPanel(events = []) {
    if (!this.hasPanelTarget) return // the shared screen has no commands
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
