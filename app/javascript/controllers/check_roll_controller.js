import { Controller } from "@hotwired/stimulus"
import { animate } from "animejs"
import { play } from "sound"

// A check landing (Campaign#check!, FieldUse#approve!): for a line that
// arrives live, the whole table watches the number spin and stop, then the
// verdict is stamped. Lines rendered with the page just sit in the log.
// On a phone controller only your own character's rolls play (the shared
// screen shows everyone's).
const SPIN_MS = 1100
const HOLD_MS = 1500

export default class extends Controller {
  static values = { result: Object }

  connect() {
    if (this.element.dataset.chatLineLiveValue !== "true" || this.element.dataset.rolled) return
    if (document.body.dataset.view === "controller" && !this.mine) return // the shared screen shows it
    this.element.dataset.rolled = "true"
    // Several at once (the whole party rolling) take turns.
    // Broadcasts can land out of order: gather the batch, then go in order.
    const queue = (window.__checkQueue ||= [])
    queue.push({ ...this.resultValue, id: Number(this.element.dataset.chatLineIdValue) })
    if (queue.length > 1) return
    setTimeout(() => {
      queue.sort((a, b) => a.id - b.id)
      show(queue)
    }, 150)
  }

  get mine() {
    const seated = document.querySelector("[data-seat-character]")?.dataset.seatCharacter
    return seated && String(this.resultValue.character_id) === seated
  }
}

function show(queue) {
  const result = queue[0]
  if (!result) return
  const el = document.createElement("div")
  el.className = "check-moment"
  el.setAttribute("aria-hidden", "true")
  el.innerHTML = `
    <p class="check-moment__who"></p>
    <p class="check-moment__why"></p>
    <p class="check-moment__odds"></p>
    <p class="check-moment__roll">0</p>
    <p class="check-moment__verdict"></p>`
  el.querySelector(".check-moment__who").textContent = `${result.name} · ${result.skill || result.stat?.toUpperCase()} · ${result.difficulty}`
  el.querySelector(".check-moment__why").textContent = result.move || (result.reason ? `to ${result.reason}` : "")
  el.querySelector(".check-moment__odds").textContent = `needs ${result.chance} or under`
  document.body.append(el)

  const number = el.querySelector(".check-moment__roll")
  const verdict = el.querySelector(".check-moment__verdict")
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches
  const land = () => {
    number.textContent = result.roll
    verdict.textContent = result.success ? "Success!" : "Failure"
    el.classList.add(result.success ? "is-success" : "is-failure")
    play(result.success ? "check_pass" : "check_fail")
    if (!reduced) animate(verdict, { scale: [2.2, 1], opacity: [0, 1], duration: 320, ease: "outBack" })
    setTimeout(() => {
      el.remove()
      queue.shift()
      show(queue)
    }, HOLD_MS)
  }
  if (reduced) return land()

  const counter = { n: 1 }
  animate(counter, {
    n: [1, 100 * 3 + result.roll], duration: SPIN_MS, ease: "outCubic",
    onUpdate: () => { number.textContent = String(Math.floor(counter.n) % 100 + 1) },
    onComplete: land
  })
  play("blip")
}
