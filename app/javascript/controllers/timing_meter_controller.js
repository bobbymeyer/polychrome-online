import { Controller } from "@hotwired/stimulus"
import { play } from "sound"
import { setting } from "storage"
import { reducedMotion } from "screen"

// The timing meter (Mario RPG's timed hits): when you confirm a move, a
// needle sweeps a bar. Stop it on the mark (tap, Space, Enter or Z) for a
// Perfect: the move lands a quarter harder (Battle::Resolver#perfect).
// Missing it costs nothing. It gives up after a few seconds, as a normal hit.
//
// A setting for this device, turned on and off in the account menu beside
// Sound and Fast animations (setting_controller, the same key); off by
// default for reduced motion.
const SETTING_KEY = "polychrome.meter"
const SWEEP_MS = 900
const GIVE_UP_MS = 3000
const ZONE = [ 0.84, 0.97 ] // the mark, as a share of the bar

export default class extends Controller {
  get enabled() {
    return setting(SETTING_KEY, !reducedMotion())
  }

  // A move's form is about to go: run the meter first.
  intercept(event) {
    const form = event.target
    if (form.dataset.timed || !this.enabled) return
    if (form.querySelector('input[name="command[kind]"]')?.value !== "ability") return

    event.preventDefault()
    event.stopPropagation()
    this.run((result) => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "command[timing]"
      input.value = result
      form.append(input)
      form.dataset.timed = "true"
      form.requestSubmit()
    })
  }

  run(done) {
    const overlay = document.createElement("div")
    overlay.className = "timing-meter"
    overlay.innerHTML = `
      <p class="timing-meter__prompt">Stop it on the mark!</p>
      <div class="timing-meter__bar">
        <span class="timing-meter__zone" style="left: ${ZONE[0] * 100}%; width: ${(ZONE[1] - ZONE[0]) * 100}%"></span>
        <span class="timing-meter__needle"></span>
      </div>
      <p class="timing-meter__result" aria-live="assertive"></p>`
    overlay.dataset.turboPermanent = "" // a refresh leaves it be (motion/keep)
    document.body.append(overlay)
    const needle = overlay.querySelector(".timing-meter__needle")
    const started = performance.now()
    let position = 0
    let finished = false

    const frame = (now) => {
      if (finished) return
      const t = ((now - started) % (SWEEP_MS * 2)) / SWEEP_MS
      position = t <= 1 ? t : 2 - t // there and back
      needle.style.left = `${position * 100}%`
      if (now - started > GIVE_UP_MS) return stop(true)
      requestAnimationFrame(frame)
    }

    const stop = (timedOut = false) => {
      if (finished) return
      finished = true
      window.removeEventListener("keydown", onKey, true)
      const perfect = !timedOut && position >= ZONE[0] && position <= ZONE[1]
      overlay.classList.add(perfect ? "is-perfect" : "is-good")
      overlay.querySelector(".timing-meter__result").textContent = perfect ? "PERFECT!" : timedOut ? "Too slow: a normal hit" : "Good"
      play(perfect ? "check_pass" : "blip")
      setTimeout(() => { overlay.remove(); done(perfect ? "perfect" : "good") }, perfect ? 650 : 400)
    }

    const onKey = (event) => {
      if (![" ", "Enter", "z", "Z"].includes(event.key)) return
      event.preventDefault()
      event.stopImmediatePropagation()
      stop()
    }
    overlay.addEventListener("pointerdown", (event) => { event.preventDefault(); stop() })
    window.addEventListener("keydown", onKey, true)
    requestAnimationFrame(frame)
  }
}
