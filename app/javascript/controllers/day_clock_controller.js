import { Controller } from "@hotwired/stimulus"
import { reducedMotion } from "screen"

// The day clock (campaigns/tables/_day_clock): when the part of the day
// moves on, the dial turns forward from where this page last saw it, round
// into the next day, instead of jumping, whenever its turn changes (on a
// refresh the dial stays and its value moves). Where it was is kept here,
// for the page's life, for a dial that's new to the page.
const seen = new Map() // campaign id => the turn last shown, in degrees
const FULL = 360

export default class extends Controller {
  static targets = ["dial"]
  static values = { turn: Number, campaign: Number }

  turnValueChanged() {
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
