import { Controller } from "@hotwired/stimulus"

// The last few lines said at the table, under the dialogue box, so nobody
// has to open the log to follow the story: players' own lines, whispers,
// choices settled, rooms found. The log drawer (#chat_log) stays the
// record; this only mirrors its tail, once a line is readable there (a
// dialogue line after the box has typed it).
//
// A whisper that reaches you also pops up for a moment, since it's meant
// for you alone.
const TOAST_MS = 7000

export default class extends Controller {
  static targets = ["list"]
  static values = { seat: String, count: { type: Number, default: 4 } }

  connect() {
    this.log = document.getElementById("chat_log")
    if (!this.log) return

    this.seen = new Set([...this.log.children].map((li) => li.id))
    this.render()
    this.observer = new MutationObserver(() => this.changed())
    this.observer.observe(this.log, { childList: true, subtree: true, attributes: true, attributeFilter: ["class", "hidden"] })
    // The choice panel can come or go after its line does: look again when it does.
    this.asking = this.askingNow()
    this.panelObserver = new MutationObserver(() => {
      if (this.askingNow() === this.asking) return
      this.asking = this.askingNow()
      this.render()
    })
    this.panelObserver.observe(this.element.closest(".table") || document.body, { childList: true, subtree: true })
  }

  disconnect() {
    this.observer?.disconnect()
    this.panelObserver?.disconnect()
  }

  askingNow() {
    return Boolean(document.querySelector("#table_choice .choice"))
  }

  changed() {
    this.render()
    for (const li of this.log.children) {
      if (this.seen.has(li.id) || li.classList.contains("is-pending")) continue
      this.seen.add(li.id)
      if (li.classList.contains("chat-line--whisper") && li.dataset.chatLineSpeakerValue !== this.seatValue) toast(li)
    }
  }

  render() {
    // A question the table is still deciding is in the choice panel, right under this: not twice.
    const asking = this.askingNow()
    const lines = [...this.log.children]
      .filter((li) => !li.classList.contains("is-pending") && !li.hidden && li !== this.inTheBox() && !(asking && li.dataset.choice))
      .slice(-this.countValue)
    this.listTarget.replaceChildren(...lines.map(quiet))
    this.element.hidden = lines.length === 0
  }

  // The line the dialogue box is still showing, if any: said once is
  // enough. Once another is being typed, the one before is only here.
  inTheBox() {
    if (!document.querySelector("section.dialogue:not([hidden])")) return null
    const said = [...this.log.children].filter((li) => li.dataset.chatLineDialogueValue === "true")
    if (said.some((li) => li.classList.contains("is-pending"))) return null
    return said.at(-1) || null
  }
}

// A copy of a log line with nothing live left in it: no ids, controllers
// or buttons (the line in the log keeps those).
function quiet(li) {
  const copy = li.cloneNode(true)
  copy.removeAttribute("id")
  for (const el of [copy, ...copy.querySelectorAll("*")]) {
    el.removeAttribute("id")
    el.removeAttribute("data-controller")
    el.removeAttribute("data-action")
  }
  copy.querySelectorAll("form, button").forEach((el) => el.remove())
  return copy
}

function toast(li) {
  const el = document.createElement("div")
  el.className = "toast"
  el.setAttribute("role", "status")
  const who = document.createElement("strong")
  who.textContent = `Whisper from ${li.dataset.chatLineSpeakerValue || "someone"}`
  const said = document.createElement("p")
  said.textContent = (li.querySelector(".chat-line__body") || li).textContent.trim()
  el.append(who, said)
  el.addEventListener("click", () => el.remove())
  document.body.append(el)
  setTimeout(() => el.remove(), TOAST_MS)
}
