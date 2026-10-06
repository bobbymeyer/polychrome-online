import { Controller } from "@hotwired/stimulus"
import { animate } from "animejs"
import { holdMusic, releaseMusic } from "sound"
import { seen, markSeen } from "storage"
import { reducedMotion } from "screen"

// The table stops for a moment: a line with a card cue (a deadline passing,
// someone awakening) brings up that cue's card over everything, the recap
// included. One controller for every card; each card is a <dialog> on the
// page that says how it plays:
//
//   data-moment-cue="deadline"           which line's cue brings it up
//   data-moment-hold="4200"              how long it stays up (a click puts it away)
//   data-moment-music="hold"             the scene's music holds still meanwhile
//   data-moment-field="line"             filled from the line's card data (or its text, for "line")
//   data-moment-field="portrait"         a face: the card's portrait, or a plate with an initial
//   data-moment-enter="drop" data-moment-delay="220"   how it comes in (drop, slam, slide, pop)
//   data-moment-turn="1400"              turns over (the "is-turned" class) after that long
//
// The line's own cue plays its sound (chat_line_controller).
const REPLAY_MS = 20000
const SEEN_KEY = "polychrome.cardsSeen"
const ENTRANCES = {
  drop: { translateY: ["-120%", "0%"], opacity: [0, 1], duration: 360, ease: "outExpo" },
  slam: { scale: [1.5, 1], opacity: [0, 1], duration: 460, ease: "outBack" },
  slide: { translateX: ["-40px", "0px"], opacity: [0, 1], duration: 320, ease: "outQuad" },
  pop: { scale: [0.6, 1], opacity: [0, 1], duration: 420, ease: "outBack" }
}

// Each browser shows a card once, live or replayed (storage.js; in a private window it may show again, no harm).

export default class extends Controller {
  connect() {
    // A card's line that arrived a moment ago, before this page was up (the
    // GM who set it off comes back to the table on a fresh page): shown once.
    // The latest of them, by id: the log keeps its newest line first (campaigns/tables/_chat_log).
    const last = [ ...this.element.querySelectorAll("[data-chat-line-cue-value]") ]
      .filter((line) => this.card(line.dataset.chatLineCueValue))
      .reduce((latest, line) => (!latest || Number(line.dataset.chatLineIdValue) > Number(latest.dataset.chatLineIdValue) ? line : latest), null)
    if (!last) return

    const id = Number(last.dataset.chatLineIdValue)
    if (!(Date.now() - Date.parse(last.dataset.saidAt || "") < REPLAY_MS) || seen(SEEN_KEY, id)) return
    let data = {}
    try { data = JSON.parse(last.dataset.chatLineCardValue || "{}") } catch { /* the line's words will do */ }
    this.present(last.dataset.chatLineCueValue, id, data, last.querySelector(".chat-line__body")?.innerText.trim() || "")
  }

  disconnect() {
    clearTimeout(this.timer)
    clearTimeout(this.turnTimer)
  }

  arrive(event) {
    const line = event.detail?.line
    if (line && this.card(line.cueValue)) this.present(line.cueValue, line.idValue, line.cardValue || {}, line.text)
  }

  dismiss() {
    const dialog = this.shown
    if (!dialog) return

    if (this.shownId) markSeen(SEEN_KEY, this.shownId, { cap: 30 }) // seen once it's been up and put away (a page torn down mid-card shows it again)
    clearTimeout(this.timer)
    clearTimeout(this.turnTimer)
    if (dialog.open) dialog.close()
    if (dialog.dataset.momentMusic === "hold") releaseMusic()
    this.shown = null
  }

  card(cue) {
    return cue && this.element.querySelector(`dialog[data-moment-cue="${cue}"]`)
  }

  present(cue, id, data, text) {
    if (this.shown) this.dismiss()
    const dialog = this.card(cue)
    this.shown = dialog
    this.shownId = id
    dialog.querySelectorAll("[data-moment-field]").forEach((el) => {
      const field = el.dataset.momentField
      if (field === "portrait") return this.fillPortrait(el, data)

      el.textContent = data[field] || (field === "line" ? text : "") || ""
      el.hidden = !el.textContent
    })

    dialog.querySelector("[data-moment-turn]")?.classList.remove("is-turned")
    if (!dialog.open) dialog.showModal()
    if (dialog.dataset.momentMusic === "hold") holdMusic()
    const still = reducedMotion()
    if (!still) {
      dialog.querySelectorAll("[data-moment-enter]").forEach((el) => {
        animate(el, { ...ENTRANCES[el.dataset.momentEnter], delay: Number(el.dataset.momentDelay || 0) })
      })
    }
    const turning = dialog.querySelector("[data-moment-turn]")
    if (turning) this.turnTimer = setTimeout(() => turning.classList.add("is-turned"), still ? 0 : Number(turning.dataset.momentTurn))
    this.timer = setTimeout(() => this.dismiss(), Number(dialog.dataset.momentHold || 5000))
  }

  // A face: the portrait, or a plate in their colour with their initial.
  fillPortrait(el, data) {
    let face
    if (data.portrait) {
      face = document.createElement("img")
      face.src = data.portrait
      face.alt = ""
    } else {
      face = document.createElement("span")
      face.className = "awakening-card__plate"
      face.textContent = (data.name || "?").charAt(0)
      face.style.cssText = data.plate || ""
    }
    el.replaceChildren(face)
  }
}
