import { Controller } from "@hotwired/stimulus"
import { reducedMotion } from "screen"
import { animate } from "animejs"
import { play } from "sound"

// A check landing (Campaign#check!, FieldUse#approve!): for a line that
// arrives live, the whole table watches the number spin and stop, then each
// modifier in turn moves it (+12 Agi, +15 Knight), then the verdict is
// stamped against what was needed. High is good, everywhere. Lines
// rendered with the page just sit in the log. On a phone controller only
// your own character's rolls play (the shared screen shows everyone's).
const SPIN_MS = 1100
const STEP_MS = 550
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
    <p class="check-moment__steps"></p>
    <p class="check-moment__verdict"></p>`
  el.querySelector(".check-moment__who").textContent = `${result.name} · ${result.skill || result.stat?.toUpperCase()} · ${result.difficulty}`
  el.querySelector(".check-moment__why").textContent = result.move || (result.reason ? `to ${result.reason}` : "")
  el.querySelector(".check-moment__odds").textContent = `needs ${result.needed} or over`
  el.dataset.turboPermanent = "" // a refresh leaves it be (motion/keep)
  document.body.append(el)

  const number = el.querySelector(".check-moment__roll")
  const steps = el.querySelector(".check-moment__steps")
  const verdict = el.querySelector(".check-moment__verdict")
  const modifiers = result.modifiers || []
  const reduced = reducedMotion()
  const signed = (n) => `${n < 0 ? "−" : "+"}${Math.abs(n)}`
  const chip = (m) => {
    const b = document.createElement("b")
    b.className = `check-moment__step ${m.amount < 0 ? "is-down" : "is-up"}`
    b.textContent = `${signed(m.amount)} ${m.label}`
    steps.append(b)
    return b
  }
  const verdictIn = () => {
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
  // Each modifier in turn: its chip comes on and the number moves by it.
  const step = (i, from) => {
    if (i >= modifiers.length) return setTimeout(verdictIn, modifiers.length ? 250 : 0)
    const to = from + modifiers[i].amount
    const b = chip(modifiers[i])
    animate(b, { scale: [1.6, 1], opacity: [0, 1], duration: 260, ease: "outBack" })
    number.classList.add(modifiers[i].amount < 0 ? "is-down" : "is-up")
    play("blip")
    const counter = { n: from }
    animate(counter, {
      n: [from, to], duration: STEP_MS * 0.6, ease: "outQuad",
      onUpdate: () => { number.textContent = String(Math.round(counter.n)) },
      onComplete: () => { number.textContent = String(to); number.classList.remove("is-up", "is-down"); setTimeout(() => step(i + 1, to), STEP_MS * 0.4) }
    })
  }
  const land = () => {
    number.textContent = result.roll
    if (reduced) {
      modifiers.forEach(chip)
      number.textContent = result.total ?? result.roll
      return verdictIn()
    }
    step(0, result.roll)
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
