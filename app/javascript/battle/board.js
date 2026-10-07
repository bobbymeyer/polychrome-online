import { play } from "sound"
import { animateBar } from "motion/changes"

// The battle board while a beat plays (battle_player_controller): finding
// units on it, changing it live as events land, and the transient effects
// drawn over it. Everything here is undone when the beat ends and the board
// after it is swapped in.
export class Board {
  // element: the battle page (its data-boss-down names the boss for the
  // victory banner); abilities: the beat's, set as each beat starts.
  constructor({ element, container, stage, fx, rail = null, tally = null, words = {}, cries = {} }) {
    Object.assign(this, { element, container, stage, fx, rail, tally, words, cries, abilities: {}, deltas: {}, round: null })
  }

  get bossDown() {
    return this.element.dataset.bossDown
  }

  get bossAway() {
    return this.element.dataset.bossAway
  }

  // The bosses' unit ids, to tell a boss that fell from one that got away (the victory event says who left).
  get bossIds() {
    return JSON.parse(this.element.dataset.bossIds || "[]")
  }

  // --- lookups ---

  unitEl(id) {
    return this.container.querySelector(`[data-unit="${CSS.escape(id)}"]`)
  }

  rosterEl(id) {
    return this.container.querySelector(`[data-roster="${CSS.escape(id)}"]`)
  }

  sprite(id) {
    return this.unitEl(id)?.querySelector("[data-sprite]")
  }

  party() {
    return [...this.container.querySelectorAll(".unit--party [data-sprite]")]
  }

  // Party members face left (toward the enemies), enemies face right.
  facing(id) {
    return this.unitEl(id)?.classList.contains("unit--party") ? -1 : 1
  }

  // --- live changes ---

  setActive(id, { quick = false } = {}) {
    if (id) this.actor = id // damage and healing name no actor: it's whoever is acting
    this.container.querySelectorAll(".is-active").forEach((el) => el.classList.remove("is-active"))
    if (id) [this.unitEl(id), this.rosterEl(id)].forEach((el) => el?.classList.add("is-active"))
    this.railActive(id, quick)
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
    const from = parseFloat(bar.style.width)
    bar.style.width = `${pct}%`
    animateBar(bar, from) // a ghost of the old length, a beat longer (motion/changes)
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

  // A status on, with what it carries (turns left, a barrier's points, a
  // blade's type), or off. The unit wears the ones that show on the sprite.
  setStatus(id, status, on, { turns = null, amount = null, type = null } = {}) {
    ;[this.unitEl(id), this.rosterEl(id)].forEach((el) => {
      const badges = el?.querySelector("[data-badges]")
      if (!badges) return
      let badge = badges.querySelector(`[data-status="${CSS.escape(status)}"]`)
      if (on) {
        if (!badge) {
          badge = document.createElement("li")
          badge.className = `badge badge--${status}`
          badge.dataset.status = status
          badges.append(badge)
        }
        const count = status === "shield" ? amount : turns
        badge.replaceChildren(`${this.statusName(status)}${type ? ` ${type}` : ""}`)
        if (count !== null && count !== undefined) {
          const b = document.createElement("b")
          b.textContent = count
          badge.append(b)
        }
        if (turns !== null) badge.dataset.turns = turns
      } else {
        badge?.remove()
      }
    })
    const unit = this.unitEl(id)
    const marks = { aggro: "is-guarding", cover: "is-guarding", charged: "is-charged", shield: "is-shielded", away: "is-away", airborne: "is-away", doom: "is-doomed" }
    if (unit && marks[status]) unit.classList.toggle(marks[status], on)
  }

  // A stat up or down, as a badge with its arrow and turns.
  setBuff(id, stat, on, { up = true, turns = null } = {}) {
    ;[this.unitEl(id), this.rosterEl(id)].forEach((el) => {
      const badges = el?.querySelector("[data-badges]")
      if (!badges) return
      let badge = badges.querySelector(`[data-buff="${CSS.escape(stat)}"]`)
      if (!on) return badge?.remove()
      if (!badge) {
        badge = document.createElement("li")
        badge.dataset.buff = stat
        badges.append(badge)
      }
      badge.className = `badge badge--${up ? "up" : "down"}`
      badge.replaceChildren(`${this.statName(stat)} ${up ? "↑" : "↓"}`)
      if (turns !== null && turns !== undefined) {
        const b = document.createElement("b")
        b.textContent = turns
        badge.append(b)
        badge.dataset.turns = turns
      }
    })
  }

  // A barrier taking a blow: its points, on its badge.
  setShield(id, left) {
    ;[this.unitEl(id), this.rosterEl(id)].forEach((el) => {
      const b = el?.querySelector('[data-status="shield"] b')
      if (b) b.textContent = left
    })
  }

  // --- this round: who goes when, and what it came to ---

  // The round's order as plates on the rail: each unit's plate and name, to
  // be lifted when they act and struck when they're done.
  setOrder(order) {
    if (!this.rail) return
    this.rail.replaceChildren(...order.map((id) => {
      const li = document.createElement("li")
      li.className = "turn-rail__plate"
      li.dataset.rail = id
      const unit = this.unitEl(id)
      const plate = unit?.querySelector(".sprite__plate, .sprite__image")?.cloneNode(true)
      if (plate) li.append(plate)
      const name = document.createElement("span")
      name.textContent = unit?.querySelector(".unit__label")?.textContent || id
      li.append(name)
      if (unit?.classList.contains("unit--enemy")) li.classList.add("is-enemy")
      return li
    }))
    this.rail.hidden = order.length === 0
  }

  railActive(id, quick) {
    if (!this.rail) return
    this.rail.querySelectorAll(".is-active").forEach((el) => el.classList.remove("is-active"))
    if (!id) return
    // A second go (haste, One More) gets a plate of its own, after the first.
    let plate = [...this.rail.querySelectorAll(`[data-rail="${CSS.escape(id)}"]`)].find((el) => !el.classList.contains("is-done"))
    if (!plate && quick) {
      const first = this.rail.querySelector(`[data-rail="${CSS.escape(id)}"]`)
      plate = first?.cloneNode(true)
      if (plate) { plate.classList.remove("is-done", "is-active"); plate.classList.add("is-again"); first.after(plate) }
    }
    plate?.classList.add("is-active")
  }

  railDone(id) {
    const plate = this.rail?.querySelector(`[data-rail="${CSS.escape(id)}"].is-active`)
    plate?.classList.remove("is-active")
    plate?.classList.add("is-done")
  }

  railGone(id) {
    this.rail?.querySelectorAll(`[data-rail="${CSS.escape(id)}"]`).forEach((el) => el.classList.add("is-gone"))
  }

  // What the round comes to: each unit's net HP change (the roster's
  // deltas), and the dealt, healed and fallen as one line under the field.
  startRound(round) {
    this.round = round
    this.deltas = {}
    this.tallies = { dealt: {}, healed: {}, fallen: [] }
    if (this.tally) this.tally.hidden = true
    this.container.querySelectorAll("[data-delta]").forEach((el) => { el.textContent = ""; el.className = "roster__delta" })
  }

  count(kind, actor, target, amount) {
    if (!this.tallies) this.startRound(this.round)
    actor ||= this.actor
    if (kind === "damage") {
      this.deltas[target] = (this.deltas[target] || 0) - amount
      if (actor) this.tallies.dealt[actor] = (this.tallies.dealt[actor] || 0) + amount
    } else if (kind === "heal") {
      this.deltas[target] = (this.deltas[target] || 0) + amount
      if (actor) this.tallies.healed[actor] = (this.tallies.healed[actor] || 0) + amount
    } else if (kind === "ko") {
      this.tallies.fallen.push(target)
    }
  }

  endRound() {
    this.restoreDeltas()
    if (!this.tally || !this.tallies) return
    const name = (id) => this.unitEl(id)?.querySelector(".unit__label")?.textContent || this.rosterEl(id)?.querySelector(".roster__name")?.firstChild?.textContent?.trim() || id
    const parts = [
      ...Object.entries(this.tallies.dealt).map(([id, n]) => `${name(id)} dealt ${n}`),
      ...Object.entries(this.tallies.healed).map(([id, n]) => `${name(id)} healed ${n}`),
      ...(this.tallies.fallen.length ? [`${[...new Set(this.tallies.fallen)].map(name).join(", ")} fell`] : []), // once each: down, up, down again is one fall
    ]
    this.tally.replaceChildren()
    const label = document.createElement("strong")
    label.textContent = `Round ${this.round ?? ""}`.trim()
    this.tally.append(label, parts.length ? ` · ${parts.join(" · ")}` : " · nothing landed")
    this.tally.hidden = false
    this.seatTally()
  }

  // On the frame, the tally sits right over the roster band, however many
  // rows the roster has (its CSS can only know the band's most).
  seatTally() {
    if (!this.tally || getComputedStyle(this.tally).position !== "absolute") return
    const roster = this.container.querySelector(".roster")
    if (roster) this.tally.style.bottom = `${roster.getBoundingClientRect().height}px`
  }

  // The roster's deltas for the round, on the board as it is now.
  restoreDeltas() {
    Object.entries(this.deltas || {}).forEach(([id, delta]) => {
      const el = this.rosterEl(id)?.querySelector("[data-delta]")
      if (!el || delta === 0) return
      el.textContent = delta > 0 ? `+${delta}` : `−${-delta}`
      el.className = `roster__delta ${delta > 0 ? "is-up" : "is-down"}`
    })
  }

  // --- the world's words (Vocabulary), with the game's as a fallback ---

  word(key) {
    return this.words[key] || key.toUpperCase()
  }

  statName(stat) {
    return this.words.stats?.[stat] || stat.toUpperCase()
  }

  statusName(status) {
    return this.words.statuses?.[status] || humanize(status)
  }

  // --- transient effects in the fx layer (created and removed) ---

  // A d100 beside a unit, for the rolls that decide something: a crit, a
  // miss, a status, a steal, a getaway. High is good: green when it reached
  // what was needed. A ruling's die shows its modifiers too ("43 +12 → 55").
  die(tl, id, e, at) {
    if (!e.roll) return
    const cameIn = e.success ?? (e.roll >= e.needed)
    const steps = (e.modifiers || []).map((m) => `${m.amount < 0 ? "−" : "+"}${Math.abs(m.amount)}`).join(" ")
    const text = steps ? `${e.roll} ${steps} → ${e.total}` : String(e.roll)
    this.popup(tl, id, text, "die", at, cameIn ? "is-in" : "is-out")
  }

  popup(tl, id, text, kind, at, extra = "") {
    const anchor = this.sprite(id)
    if (!anchor) return
    const stage = this.stage.getBoundingClientRect()
    const box = anchor.getBoundingClientRect()
    const el = document.createElement("span")
    el.className = `popup popup--${kind} ${extra}`.trim()
    el.textContent = text
    el.style.top = `${box.top - stage.top + box.height * 0.3}px`
    // Numbers land at a slight tilt, never the same twice (decoration, not outcome).
    if (["damage", "heal", "poison"].includes(kind)) el.style.rotate = `${(Math.random() * 12 - 6).toFixed(1)}deg`
    this.fx.append(el)
    // Centred on the sprite, but never past the stage's edge ("SUPER EFFECTIVE!" on the end of a row).
    const half = el.offsetWidth / 2
    const centre = box.left - stage.left + box.width / 2
    el.style.left = `${Math.min(Math.max(centre, half + 4), Math.max(half + 4, stage.width - half - 4))}px`
    tl.add(el, { opacity: [0, 1, 1, 0], translateY: [8, -30, -34, -44], scale: [1.6, 1, 1, 0.9], duration: 900, ease: "outQuad" }, at)
    tl.call(() => el.remove(), at + 900)
  }

  // Cause: a streak from the actor to each target, in the move's kind (hit,
  // magic, heal, sap), drawn and gone. Several targets are struck in turn.
  streak(tl, from, targets, kind, at) {
    const origin = this.sprite(from)
    if (!origin || !targets?.length) return
    const stage = this.stage.getBoundingClientRect()
    const centre = (el) => { const r = el.getBoundingClientRect(); return [r.left - stage.left + r.width / 2, r.top - stage.top + r.height / 2] }
    const [x1, y1] = centre(origin)
    targets.forEach((id, i) => {
      const target = this.sprite(id)
      if (!target || target === origin) return
      const [x2, y2] = centre(target)
      const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
      svg.setAttribute("class", `streak streak--${kind}`)
      svg.setAttribute("viewBox", `0 0 ${stage.width} ${stage.height}`)
      const line = document.createElementNS("http://www.w3.org/2000/svg", "line")
      Object.entries({ x1, y1, x2, y2 }).forEach(([k, v]) => line.setAttribute(k, v))
      const length = Math.hypot(x2 - x1, y2 - y1)
      line.style.strokeDasharray = `${length}`
      line.style.strokeDashoffset = `${length}`
      svg.append(line)
      this.fx.append(svg)
      const start = at + i * 70
      tl.add(line, { strokeDashoffset: [length, 0], duration: 160, ease: "outQuad" }, start)
      tl.add(svg, { opacity: [1, 1, 0], duration: 320, ease: "inQuad" }, start + 160)
      tl.call(() => svg.remove(), start + 500)
    })
  }

  // A unit's line, said in the stage's dialogue box as a beat of its own (dialogue_controller#say):
  // its name, its face from the field (the sprite's image, else its plate's colour).
  speak(id, line, name = null) {
    const sprite = this.sprite(id)
    const plate = sprite?.querySelector(".sprite__plate")
    window.dispatchEvent(new CustomEvent("dialogue:say", {
      detail: {
        speaker: name || this.unitEl(id)?.querySelector(".unit__label")?.textContent || id,
        text: line, plate: plate?.getAttribute("style") || "", portrait: sprite?.querySelector("img")?.src || "", expression: "angry"
      }
    }))
  }

  banner(tl, text, at, kind = "round") {
    const el = document.createElement("div")
    el.className = `banner banner--${kind}`
    el.textContent = text
    this.fx.append(el)
    if (["victory", "defeat", "escape", "boss-down", "all-out", "phase"].includes(kind)) {
      // Thrown across the stage from the left, held, then gone.
      tl.add(el, { opacity: [0, 1, 1, 1, 0], translateX: ["-60%", "0%", "0%", "0%", "4%"], duration: 1300, ease: "outExpo" }, at)
    } else {
      tl.add(el, { opacity: [0, 1, 1, 0], translateX: [-24, 0, 0, 8], duration: kind === "round" ? 400 : 1200, ease: "outQuad" }, at)
    }
  }

  caption(tl, text, at, kind = null) {
    const el = document.createElement("div")
    el.className = `caption window${kind ? ` caption--${kind}` : ""}`
    el.textContent = text
    this.fx.append(el)
    tl.add(el, { opacity: [0, 1, 1, 0], translateX: [-32, 0, 0, 0], duration: 700, ease: "outQuad" }, at)
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
    const cry = this.cries[e.actor]
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
    this.fx.append(el)

    const hold = cry ? 1500 + Math.min(cry.length * 18, 900) : 1100
    tl.call(() => play("desperation"), at)
    tl.add(el, { opacity: [0, 1, 1, 0], translateX: ["-40%", "0%", "0%", "30%"], duration: hold, ease: "outExpo" }, at)
    tl.add(figure, { translateX: [-60, 0], scale: [1.4, 1], duration: 380, ease: "outBack" }, at + 80)
    tl.call(() => el.remove(), at + hold)
    return hold
  }
}

export function humanize(token) {
  const s = String(token).replaceAll("_", " ")
  return s.charAt(0).toUpperCase() + s.slice(1)
}
