import { gesture } from "motion/gestures"
import { play, setMusic } from "sound"
import { humanize } from "battle/board"

// How each of the resolver's events plays on the board (docs/HANDOFF.md §6):
// the entries it adds to the beat's anime.js timeline, starting at `at`,
// and how long it takes (ms). b is the Board. Every number shown comes from
// the event; nothing here decides an outcome (§12).
const STEPS = {
  round_start(b, tl, e, at) {
    tl.call(() => b.startRound(e.round), at)
    b.banner(tl, `Round ${e.round}`, at)
    return 400
  },
  round_end(b, tl, e, at) {
    tl.call(() => b.endRound(), at)
    return 200
  },
  // This round's order, on the rail above the field.
  turn_order(b, tl, e, at) {
    tl.call(() => b.setOrder(e.order), at)
    return 160
  },
  turn_start(b, tl, e, at) {
    tl.call(() => b.setActive(e.unit, { quick: e.quick }), at)
    return 120
  },
  turn_end(b, tl, e, at) {
    tl.call(() => { b.railDone(e.unit); b.setActive(null) }, at)
    return 60
  },
  command_accepted(b, tl, e, at) {
    tl.call(() => b.setReady(e.actor, true), at)
    return 0
  },
  jump(b, tl, e, at) {
    // Up and out of the frame, and out of reach, until its next turn.
    tl.add(b.sprite(e.actor), { translateY: [0, -220], opacity: [1, 0], duration: 420, ease: "inQuad" }, at)
    return 500
  },
  away(b, tl, e, at) {
    // Off the field (hiding, banished, knocked back) until it comes back.
    tl.add(b.sprite(e.unit), { opacity: [1, 0], scale: [1, 0.8], duration: 360, ease: "inQuad" }, at)
    b.popup(tl, e.unit, e.unit === e.actor ? "HIDDEN" : "SENT AWAY", "status", at)
    return 420
  },
  shielded(b, tl, e, at) {
    tl.call(() => b.setShield(e.target, e.left), at)
    b.popup(tl, e.target, e.left > 0 ? `BARRIER −${e.absorbed}` : "BARRIER BROKEN", "status", at)
    return 260
  },
  confused(b, tl, e, at) {
    if (e.target) b.popup(tl, e.actor, "CONFUSED", "status", at)
    return 220
  },
  hp_paid(b, tl, e, at) {
    b.popup(tl, e.actor, `−${e.amount} ${b.word("hp")}`, "status", at)
    return 240
  },
  charging(b, tl, e, at) {
    b.popup(tl, e.actor, "CHARGING", "status", at)
    gesture(tl, b.sprite(e.actor), "shake", at)
    return 360
  },
  mp_lost(b, tl, e, at) {
    b.popup(tl, e.target, `−${e.amount} ${b.word("mp")}`, "status", at)
    return 260
  },
  back(b, tl, e, at) {
    tl.add(b.sprite(e.unit), { opacity: [0, 1], scale: [0.8, 1], duration: 300, ease: "outQuad" }, at)
    return 340
  },
  land(b, tl, e, at) {
    tl.add(b.sprite(e.actor), { translateY: [-220, 0], opacity: [0, 1], duration: 260, ease: "inExpo" }, at)
    if (e.target) gesture(tl, b.stage, "shake", at + 240)
    return 320
  },
  covered(b, tl, e, at) {
    b.popup(tl, e.unit, "COVER!", "status", at)
    gesture(tl, b.sprite(e.unit), "lunge", at, b.facing(e.unit))
    return 380
  },
  counter(b, tl, e, at) {
    b.die(tl, e.actor, e, at)
    b.popup(tl, e.actor, "COUNTER!", "crit", at)
    return 300
  },
  second_wind(b, tl, e, at) {
    tl.call(() => { b.setKo(e.target, false); b.setHp(e.target, e.hp) }, at)
    b.popup(tl, e.target, "SECOND WIND!", "perfect", at)
    gesture(tl, b.sprite(e.target), "bounce", at)
    return 700
  },
  mp_restored(b, tl, e, at) {
    tl.call(() => b.addMp(e.target, e.amount), at)
    b.popup(tl, e.target, `+${e.amount} ${b.word("mp")}`, "status", at)
    return 250
  },
  custom_action(b, tl, e, at) {
    // A player's own idea, in their words.
    b.caption(tl, `“${e.text}”`, at, "custom")
    return Math.max(gesture(tl, b.sprite(e.actor), "bounce", at), 700)
  },
  custom_roll(b, tl, e, at) {
    b.die(tl, e.actor, e, at)
    b.banner(tl, e.success ? "It works!" : "No luck", at + 150, "gm")
    if (e.line) b.caption(tl, e.line, at + 500, "narration")
    return e.line ? 1400 : 900
  },
  custom_unruled(b, tl, e, at) {
    b.caption(tl, "No ruling: attacks instead", at)
    return 500
  },
  desperation(b, tl, e, at) {
    return b.cutIn(tl, e, at)
  },
  // A reaction: a script's "when" rule fires out of turn (a counter, a last breath).
  reacts(b, tl, e, at) {
    const word = { hit: "COUNTER!", ally_falls: "VENGEANCE!", falls: "LAST BREATH!" }[e.trigger] || "REACTS!"
    b.popup(tl, e.actor, word, "crit", at)
    gesture(tl, b.sprite(e.actor), "shake", at)
    return 500
  },
  // A creature says a line as its rule fires: the telegraph before the blow, said in the stage's
  // dialogue box as a beat of its own (dialogue_controller#say), with its face from the field.
  says(b, tl, e, at) {
    gesture(tl, b.sprite(e.actor), "pop", at)
    tl.call(() => b.speak(e.actor, e.line), at)
    return 900
  },
  // A boss becomes its next form: the board after the beat has it; here, the slab, its line in the
  // box, and its own music if the form brings any.
  phase(b, tl, e, at) {
    gesture(tl, b.sprite(e.actor), "flash", at)
    gesture(tl, b.sprite(e.actor), "shake", at + 200)
    b.banner(tl, `${e.name}!`, at + 300, "phase")
    if (e.music) tl.call(() => setMusic(e.music, { cut: true }), at + 300)
    if (e.line) tl.call(() => b.speak(e.actor, e.line, e.name), at + 1500)
    return 1700
  },
  unit_joined(b, tl, e, at) {
    // The board after the beat has them; here, the entrance.
    b.banner(tl, e.guest ? `${e.name} joins the party!` : `${e.name} appears!`, at, "gm")
    return 900
  },
  summoned(b, tl, e, at) {
    // Small summons: a creature's name, and it's already moving.
    b.caption(tl, `${e.name}!`, at, "skill")
    return 500
  },
  unit_left(b, tl, e, at) {
    gesture(tl, b.sprite(e.unit), "fade", at)
    b.banner(tl, `${e.name} leaves`, at, "gm")
    return 900
  },
  attack(b, tl, e, at) {
    if (e.perfect) b.popup(tl, e.actor, "PERFECT!", "perfect", at)
    b.streak(tl, e.actor, e.targets, "hit", at + 120)
    return gesture(tl, b.sprite(e.actor), "lunge", at, b.facing(e.actor))
  },
  item_used(b, tl, e, at) {
    b.streak(tl, e.actor, e.targets, "heal", at + 200)
    b.caption(tl, e.name || e.item, at, "item")
    return Math.max(gesture(tl, b.sprite(e.actor), "bounce", at), 450)
  },
  cast(b, tl, e, at) {
    const ability = b.abilities[e.ability] || {}
    b.caption(tl, ability.name || e.ability, at, ability.kind)
    if (e.perfect) b.popup(tl, e.actor, "PERFECT!", "perfect", at)
    if (e.mp_cost) tl.call(() => b.addMp(e.actor, -e.mp_cost), at)
    // What it's doing to whom: a streak in the move's kind.
    const primitives = (ability.effects || []).map((x) => x.primitive)
    const streak = primitives.some((x) => ["heal", "revive", "shield", "buff", "cleanse"].includes(x)) ? "heal"
      : primitives.some((x) => ["drain", "sap"].includes(x)) ? "sap"
      : ability.kind === "magic" ? "magic" : "hit"
    b.streak(tl, e.actor, e.targets, streak, at + 200)
    return Math.max(gesture(tl, b.sprite(e.actor), ability.gesture || "flash", at, b.facing(e.actor)), 450)
  },
  damage(b, tl, e, at) {
    tl.call(() => { b.setHp(e.target, e.hp); b.count("damage", e.actor, e.target, e.amount) }, at)
    b.popup(tl, e.target, String(e.amount), e.status === "poison" ? "poison" : "damage", at)
    gesture(tl, b.sprite(e.target), e.status === "poison" ? "tint" : "shake", at)
    // The type chart, said out loud.
    if (e.effectiveness > 100) {
      b.popup(tl, e.target, "SUPER EFFECTIVE!", "weak", at + 120)
      gesture(tl, b.stage, "flash", at + 120)
      return 560
    }
    if (e.effectiveness < 100) {
      b.popup(tl, e.target, "NOT VERY EFFECTIVE", "resist", at + 120)
      return 520
    }
    return 380
  },
  heal(b, tl, e, at) {
    tl.call(() => { b.setHp(e.target, e.hp); b.count("heal", e.actor, e.target, e.amount) }, at)
    b.popup(tl, e.target, String(e.amount), "heal", at)
    gesture(tl, b.sprite(e.target), "float", at)
    return 380
  },
  crit(b, tl, e, at) {
    b.die(tl, e.actor, e, at)
    b.popup(tl, e.target, "CRIT!", "crit", at)
    gesture(tl, b.stage, "flash", at)
    return 260
  },
  miss(b, tl, e, at) {
    b.die(tl, e.reason === "resisted" ? e.target : e.actor, e, at)
    b.popup(tl, e.target || e.actor, { immune: e.damage_type ? "NO EFFECT" : "IMMUNE", nothing_to_cure: "NO EFFECT", nothing_to_steal: "NOTHING", steal_failed: "MISSED" }[e.reason] || "MISS", "miss", at)
    return 380
  },
  // One More (a world's rule): the blow found a weakness, and they go again.
  one_more(b, tl, e, at) {
    tl.call(() => play("one_more"), at)
    b.banner(tl, "ONE MORE!", at, "one-more")
    gesture(tl, b.sprite(e.actor), "bounce", at)
    gesture(tl, b.stage, "flash", at)
    return 800
  },
  // All-Out Attack: every enemy is down, and the whole party piles in.
  all_out(b, tl, e, at) {
    tl.call(() => play("all_out"), at)
    b.banner(tl, "ALL-OUT ATTACK!", at, "all-out")
    ;(e.units || []).forEach((id, i) => gesture(tl, b.sprite(id), "bounce", at + i * 80))
    gesture(tl, b.stage, "flash", at + 500)
    return 1400
  },
  status_applied(b, tl, e, at) {
    if (e.status === "down") {
      tl.call(() => b.setStatus(e.target, e.status, true), at)
      b.popup(tl, e.target, "DOWN!", "crit", at, "status-down")
      gesture(tl, b.sprite(e.target), "shake", at)
      return 360
    }
    b.die(tl, e.target, e, at)
    tl.call(() => b.setStatus(e.target, e.status, true, { turns: e.turns, amount: e.amount, type: e.damage_type }), at)
    b.popup(tl, e.target, b.statusName(e.status), "status", at, `status-${e.status}`)
    gesture(tl, b.sprite(e.target), "tint", at)
    return 450
  },
  status_expired(b, tl, e, at) {
    tl.call(() => b.setStatus(e.target, e.status, false), at)
    if (e.reason === "cured") {
      b.popup(tl, e.target, `${b.statusName(e.status)} cured`, "status", at, `status-${e.status}`)
      return 380
    }
    return 250
  },
  // A stat up or down: an arrow with the stat's word, and a badge that lasts.
  buff_applied(b, tl, e, at) {
    const up = e.amount > 0
    tl.call(() => b.setBuff(e.target, e.stat, true, { up, turns: e.turns }), at)
    b.popup(tl, e.target, `${b.statName(e.stat)} ${up ? "↑" : "↓"}`, up ? "buff-up" : "buff-down", at)
    gesture(tl, b.sprite(e.target), up ? "bounce" : "shake", at)
    return 420
  },
  buff_expired(b, tl, e, at) {
    tl.call(() => b.setBuff(e.target, e.stat, false), at)
    return 120
  },
  ko(b, tl, e, at) {
    tl.call(() => { b.setKo(e.target, true); b.count("ko", null, e.target); b.railGone(e.target) }, at)
    b.popup(tl, e.target, "KO", "miss", at)
    return gesture(tl, b.sprite(e.target), "fade", at)
  },
  revive(b, tl, e, at) {
    tl.call(() => { b.setKo(e.target, false); b.setHp(e.target, e.hp) }, at)
    return gesture(tl, b.sprite(e.target), "pop", at)
  },
  steal(b, tl, e, at) {
    b.die(tl, e.actor, e, at)
    b.popup(tl, e.target, `Stole ${e.name}!`, "status", at)
    gesture(tl, b.sprite(e.actor), "lunge", at, b.facing(e.actor))
    return 600
  },
  scan(b, tl, e, at) {
    b.popup(tl, e.target, "Scanned", "status", at)
    return 450
  },
  defend(b, tl, e, at) {
    b.popup(tl, e.actor, "DEFEND", "miss", at)
    return gesture(tl, b.sprite(e.actor), "bounce", at)
  },
  turn_skipped(b, tl, e, at) {
    b.popup(tl, e.unit, e.reason === "sleep" ? "Zzz" : e.reason === "paralyze" ? "…" : "?", "miss", at)
    return 420
  },
  action_failed(b, tl, e, at) {
    b.popup(tl, e.actor, e.reason === "silenced" ? b.statusName("silence").toUpperCase() : `NO ${b.word("mp").toUpperCase()}`, "miss", at)
    return 420
  },
  flee(b, tl, e, at) {
    b.die(tl, e.actor, e, at)
    if (!e.success) {
      b.caption(tl, "Couldn't escape!", at)
      return 600
    }
    b.party().forEach((el) => gesture(tl, el, "slide", at, 1))
    b.banner(tl, "Escaped!", at, "escape")
    return 900
  },
  timeout(b, tl, e, at) {
    if (e.defaulted.length) b.banner(tl, "Time's up!", at)
    return e.defaulted.length ? 700 : 0
  },
  victory(b, tl, e, at) {
    // Nobody fell: the enemy got away (sent off the field). No fanfare, no hop.
    if (e.fell === false) {
      b.banner(tl, "They got away!", at, "escape")
      return 1200
    }
    b.banner(tl, "Victory!", at, "victory")
    tl.call(() => play("victory"), at)
    // The party's victory hop, as in the games.
    b.party().forEach((el, i) => { gesture(tl, el, "bounce", at + 200 + i * 80); gesture(tl, el, "bounce", at + 700 + i * 80) })
    // A boss gets its epitaph: the victory says what it beat, or that it got away (every boss left the field).
    const gone = e.gone || []
    const bossAway = b.bossIds.length && b.bossIds.every((id) => gone.includes(id))
    if (bossAway && b.bossAway) {
      b.banner(tl, b.bossAway, at + 1300, "escape")
      return 2800
    }
    if (b.bossDown) {
      b.banner(tl, b.bossDown, at + 1300, "boss-down")
      return 2800
    }
    return 1500
  },
  abandoned(b, tl, e, at) {
    b.banner(tl, "Called off", at, "defeat")
    return 1200
  },
  defeat(b, tl, e, at) {
    b.banner(tl, "Defeat", at, "defeat")
    tl.call(() => play("defeat"), at)
    return 1300
  },
  gm_override(b, tl, e, at) {
    // GM power is never hidden (§12): every override is in the log, and
    // gets a banner, except the routine auto for absent players.
    if (e.op === "auto") return 0
    b.banner(tl, `GM: ${humanize(e.op)}`, at, "gm")
    if (e.hp !== undefined) tl.call(() => b.setHp(e.unit, e.hp), at)
    return 900
  },
}

export function choreograph(b, tl, e, at) {
  return STEPS[e.type]?.(b, tl, e, at) ?? 0
}
