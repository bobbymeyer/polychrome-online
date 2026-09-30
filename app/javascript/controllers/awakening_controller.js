import { Controller } from "@hotwired/stimulus"
import { animate } from "animejs"
import { holdMusic, releaseMusic } from "sound"

// Someone awakens (Campaign#awaken!): the table stops, their face comes up,
// and turns over; their new archetype is on the other side, with what they heard. The
// line's own cue plays the jingle (chat_line_controller). Click, or wait,
// to go on.
const FLIP_AFTER_MS = 1400
// Long enough to read the back out loud at the table.
const HOLD_MS = 9500

// A card's line that arrived a moment ago, before this page was up (the GM
// who set it off comes back to the table on a fresh page): shown once here.
// Each browser shows a card once, live or replayed.
const REPLAY_MS = 20000
const SEEN_KEY = "polychrome.cardsSeen"

function seen(id) {
  try { return JSON.parse(localStorage.getItem(SEEN_KEY) || "[]").includes(id) } catch { return false }
}

function markSeen(id) {
  try {
    const ids = JSON.parse(localStorage.getItem(SEEN_KEY) || "[]").filter((i) => i !== id).slice(-30)
    localStorage.setItem(SEEN_KEY, JSON.stringify([ ...ids, id ]))
  } catch { /* private window: it may show again, no harm */ }
}

// The newest line with this cue, if it's recent and not shown here yet:
// { id, text, card }.
function recent(root, cue) {
  const lines = root.querySelectorAll(`[data-chat-line-cue-value="${cue}"]`)
  const last = lines[lines.length - 1]
  if (!last) return null
  const id = Number(last.dataset.chatLineIdValue)
  const at = Date.parse(last.dataset.saidAt || "")
  if (!(Date.now() - at < REPLAY_MS) || seen(id)) return null
  let card = {}
  try { card = JSON.parse(last.dataset.chatLineCardValue || "{}") } catch { /* no card: the line's words will do */ }
  return { id, text: last.querySelector(".chat-line__body")?.innerText.trim() || "", card }
}

export default class extends Controller {
  static targets = ["overlay", "wrap", "card", "portrait", "name", "who", "line", "job", "description"]

  connect() {
    const missed = recent(this.element, "awakening")
    if (missed) this.present(missed.id, missed.card)
  }

  disconnect() {
    clearTimeout(this.timer)
    clearTimeout(this.flipTimer)
  }

  arrive(event) {
    const line = event.detail?.line
    if (!line || line.cueValue !== "awakening") return

    this.present(line.idValue, line.cardValue || {})
  }

  present(id, card) {
    this.shownId = id // seen once it's been up and put away (a page torn down mid-card shows it again)
    this.fillPortrait(card)
    this.nameTarget.textContent = card.name || ""
    // The back says whose it is: the card is still theirs once it's turned.
    this.whoTarget.textContent = card.name ? `${card.name} awakens` : ""
    this.lineTarget.textContent = card.line || ""
    this.lineTarget.hidden = !card.line
    this.jobTarget.textContent = card.job || ""
    this.descriptionTarget.textContent = card.description || ""
    this.show()
  }

  fillPortrait(card) {
    let face
    if (card.portrait) {
      face = document.createElement("img")
      face.src = card.portrait
      face.alt = ""
    } else {
      face = document.createElement("span")
      face.className = "awakening-card__plate"
      face.textContent = (card.name || "?").charAt(0)
      face.style.cssText = card.plate || ""
    }
    this.portraitTarget.replaceChildren(face)
  }

  show() {
    clearTimeout(this.timer)
    clearTimeout(this.flipTimer)
    this.cardTarget.classList.remove("is-turned")
    if (!this.overlayTarget.open) this.overlayTarget.showModal()
    holdMusic()
    const still = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    // The wrapper comes in; the card inside is left free to turn over (stage.css).
    if (!still) animate(this.wrapTarget, { scale: [0.6, 1], opacity: [0, 1], duration: 420, ease: "outBack" })
    this.flipTimer = setTimeout(() => this.turn(), still ? 0 : FLIP_AFTER_MS)
    this.timer = setTimeout(() => this.dismiss(), HOLD_MS)
  }

  // The face turns over (stage.css does the turning).
  turn() {
    // (the reduced-motion case turns at once too: stage.css drops the transition)
    this.cardTarget.classList.add("is-turned")
  }

  dismiss() {
    if (this.shownId) markSeen(this.shownId)
    clearTimeout(this.timer)
    clearTimeout(this.flipTimer)
    if (this.overlayTarget.open) this.overlayTarget.close()
    releaseMusic()
  }
}
