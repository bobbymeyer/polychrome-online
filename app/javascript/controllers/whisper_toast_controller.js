import { Controller } from "@hotwired/stimulus"

// A whisper that reaches you pops up for a moment, since it's meant for you
// alone: the log is on the right, but a whisper shouldn't wait to be read.
// On the table, hearing each line as it lands (chat-line:arrived).
const TOAST_MS = 7000

export default class extends Controller {
  static values = { seat: String }

  arrive(event) {
    const li = event.detail.line.element
    if (!li.classList.contains("chat-line--whisper") || li.dataset.chatLineSpeakerValue === this.seatValue) return

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
}
