import { play } from "sound"

// The battle board while a beat plays (battle_player_controller): finding
// units on it, changing it live as events land, and the transient effects
// drawn over it. Everything here is undone when the beat ends and the board
// after it is swapped in.
export class Board {
  // element: the battle page (its data-boss-down names the boss for the
  // victory banner); abilities: the beat's, set as each beat starts.
  constructor({ element, container, stage, fx, words = {}, cries = {} }) {
    Object.assign(this, { element, container, stage, fx, words, cries, abilities: {} })
  }

  get bossDown() {
    return this.element.dataset.bossDown
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

  setActive(id) {
    this.container.querySelectorAll(".is-active").forEach((el) => el.classList.remove("is-active"))
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
        badge.textContent = this.statusName(status)
        badges.append(badge)
      } else if (!on) {
        existing?.remove()
      }
    })
  }

  // --- the world's words (Vocabulary), with the game's as a fallback ---

  word(key) {
    return this.words[key] || key.toUpperCase()
  }

  statusName(status) {
    return this.words.statuses?.[status] || humanize(status)
  }

  // --- transient effects in the fx layer (created and removed) ---

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

  banner(tl, text, at, kind = "round") {
    const el = document.createElement("div")
    el.className = `banner banner--${kind}`
    el.textContent = text
    this.fx.append(el)
    if (["victory", "defeat", "escape", "boss-down", "all-out"].includes(kind)) {
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
