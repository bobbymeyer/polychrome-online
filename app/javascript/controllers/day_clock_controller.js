import { Controller } from "@hotwired/stimulus"
import { reducedMotion } from "screen"

// The day clock (campaigns/tables/_day_clock): when the part of the day
// moves on, the dial turns forward from where this page last saw it, round
// into the next day, instead of jumping. The table panel is replaced as
// time passes, so where it was is kept here, for the page's life.
const seen = new Map() // campaign id => the turn last shown, in degrees
const FULL = 360

export default class extends Controller {
  static targets = ["dial"]
  static values = { turn: Number, campaign: Number }

  connect() {
    const to = this.turnValue
    const from = seen.get(this.campaignValue)
    seen.set(this.campaignValue, to)
    if (from === undefined || from === to || reducedMotion()) return

    // A long wait turns once round and on to where it is, not round and round.
    const start = from - to > FULL ? to + FULL : from
    const dial = this.dialTarget
    dial.classList.add("is-still")
    dial.style.setProperty("--turn", `${start}deg`)
    dial.getBoundingClientRect() // settle there before turning
    dial.classList.remove("is-still")
    dial.style.setProperty("--turn", `${to}deg`)
  }
}
