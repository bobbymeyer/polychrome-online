import { Controller } from "@hotwired/stimulus"
import { animate } from "animejs"

// A deadline passes (Clock#fill!): the table stops for it. The date drops
// in, the clock's line is slammed across the stage in big type, and what
// the place has become sits under it. The line's own cue plays the bell
// (chat_line_controller). Click, or wait, to go on.
const HOLD_MS = 4200

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
  static targets = ["overlay", "date", "line", "place"]

  connect() {
    const missed = recent(this.element, "deadline")
    if (missed) this.present(missed.id, missed.card, missed.text)
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  arrive(event) {
    const line = event.detail?.line
    if (!line || line.cueValue !== "deadline") return

    this.present(line.idValue, line.cardValue || {}, line.text)
  }

  present(id, card, text) {
    this.shownId = id // seen once it's been up and put away (a page torn down mid-card shows it again)
    this.dateTarget.textContent = card.date || ""
    this.lineTarget.textContent = card.line || text
    this.placeTarget.textContent = card.place || ""
    this.placeTarget.hidden = !card.place
    this.show()
  }

  show() {
    clearTimeout(this.timer)
    if (!this.overlayTarget.open) this.overlayTarget.showModal()
    if (!window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      animate(this.dateTarget, { translateY: ["-120%", "0%"], opacity: [0, 1], duration: 360, ease: "outExpo" })
      animate(this.lineTarget, { scale: [1.5, 1], opacity: [0, 1], duration: 460, delay: 220, ease: "outBack" })
      animate(this.placeTarget, { translateX: ["-40px", "0px"], opacity: [0, 1], duration: 320, delay: 620, ease: "outQuad" })
    }
    this.timer = setTimeout(() => this.dismiss(), HOLD_MS)
  }

  dismiss() {
    if (this.shownId) markSeen(this.shownId)
    clearTimeout(this.timer)
    if (this.overlayTarget.open) this.overlayTarget.close()
  }
}
