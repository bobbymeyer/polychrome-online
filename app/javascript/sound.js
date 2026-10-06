// Sound (docs/DESIGN.md, "Sound"): short jingles for the moments that matter,
// and music for the scene.
//
// The jingles are synthesised here with WebAudio, from square, triangle and
// noise voices, like the consoles the game remembers. The melodies are our
// own. Music is the world's own Music book (Track): each page names the
// track for its scene in <meta name="polychrome-music">, and one audio
// element, kept across Turbo visits, crossfades between them. A linked track
// (YouTube, Spotify) can't be fetched: its player is shown instead, small, in
// the page's corner (#music_embed, kept across visits too).
//
// Browsers only allow sound after the viewer has done something, so nothing
// plays until the first click or key. Muting is per device (storage.js).
import { setting, setSetting } from "storage"

const MUTE_KEY = "polychrome.muted"
const MUSIC_VOLUME = 0.5
const FADE_MS = 600

// --- mute ------------------------------------------------------------------

export function muted() {
  return setting(MUTE_KEY, false)
}

export function setMuted(value) {
  setSetting(MUTE_KEY, value)
  if (master) master.gain.value = value ? 0 : JINGLE_VOLUME
  music.muted = value
  apply() // a linked track's player comes and goes with the mute
  document.dispatchEvent(new CustomEvent("sound:muted", { detail: { muted: value } }))
}

// --- jingles ---------------------------------------------------------------

const JINGLE_VOLUME = 0.16
let ctx = null
let master = null

function audio() {
  if (!ctx) {
    const AudioContext = window.AudioContext || window.webkitAudioContext
    if (!AudioContext) return null
    ctx = new AudioContext()
    master = ctx.createGain()
    master.gain.value = muted() ? 0 : JINGLE_VOLUME
    master.connect(ctx.destination)
  }
  if (ctx.state === "suspended") ctx.resume()
  return ctx
}

const NOTE = { C: -9, D: -7, E: -5, F: -4, G: -2, A: 0, B: 2 }
// "A4" → 440, "C#5", "Bb3".
function hz(name) {
  const [, letter, accidental, octave] = name.match(/^([A-G])([#b]?)(\d)$/)
  const semitones = NOTE[letter] + (accidental === "#" ? 1 : accidental === "b" ? -1 : 0) + (Number(octave) - 4) * 12
  return 440 * 2 ** (semitones / 12)
}

// One note: a voice with a quick attack and a decay, so it plinks rather
// than drones.
function tone(at, note, length, { wave = "square", gain = 0.5, slide = null, decay = 0.7 } = {}) {
  const osc = ctx.createOscillator()
  const env = ctx.createGain()
  osc.type = wave
  osc.frequency.setValueAtTime(typeof note === "number" ? note : hz(note), at)
  if (slide) osc.frequency.exponentialRampToValueAtTime(typeof slide === "number" ? slide : hz(slide), at + length)
  env.gain.setValueAtTime(0.0001, at)
  env.gain.exponentialRampToValueAtTime(gain, at + 0.008)
  env.gain.exponentialRampToValueAtTime(gain * decay, at + length * 0.5)
  env.gain.exponentialRampToValueAtTime(0.0001, at + length)
  osc.connect(env).connect(master)
  osc.start(at)
  osc.stop(at + length + 0.02)
}

// A burst of noise: a drum, a door, a thud.
function noise(at, length, { gain = 0.4, filter = 1200 } = {}) {
  const buffer = ctx.createBuffer(1, Math.ceil(ctx.sampleRate * length), ctx.sampleRate)
  const data = buffer.getChannelData(0)
  for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1
  const source = ctx.createBufferSource()
  source.buffer = buffer
  const lowpass = ctx.createBiquadFilter()
  lowpass.type = "lowpass"
  lowpass.frequency.value = filter
  const env = ctx.createGain()
  env.gain.setValueAtTime(gain, at)
  env.gain.exponentialRampToValueAtTime(0.0001, at + length)
  source.connect(lowpass).connect(env).connect(master)
  source.start(at)
}

// A phrase: [note, beat, beats] in one voice, at a tempo in seconds per beat.
function phrase(start, beat, notes, options) {
  notes.forEach(([note, at, beats]) => note && tone(start + at * beat, note, beats * beat, options))
}

const JINGLES = {
  // Danger, fast: a climbing figure over a pulsing bass, and a stab.
  encounter(t) {
    phrase(t, 0.055, [ [ "E4", 0, 1 ], [ "G4", 1, 1 ], [ "B4", 2, 1 ], [ "E5", 3, 1 ], [ "G5", 4, 1 ], [ "B5", 5, 1 ], [ "D6", 6, 1 ] ], { gain: 0.35 })
    phrase(t, 0.055, [ [ "E2", 0, 2 ], [ "E2", 2, 2 ], [ "E2", 4, 2 ], [ "E2", 6, 2 ] ], { wave: "triangle", gain: 0.7 })
    ;[ "E5", "B5", "E6" ].forEach((n) => tone(t + 0.44, n, 0.32, { gain: 0.22, decay: 0.4 }))
    noise(t + 0.44, 0.18, { gain: 0.35, filter: 3000 })
  },
  // Something worse: slow steps down in the dark, and a tritone.
  boss(t) {
    phrase(t, 0.16, [ [ "E2", 0, 1 ], [ "Eb2", 1, 1 ], [ "D2", 2, 1 ], [ "Db2", 3, 2 ] ], { wave: "triangle", gain: 0.8 })
    ;[ "E3", "Bb3", "E4" ].forEach((n) => tone(t + 0.64, n, 0.7, { wave: "sawtooth", gain: 0.12, decay: 0.5 }))
    noise(t + 0.64, 0.5, { gain: 0.3, filter: 500 })
  },
  // The boss's name lands: one deep hit, then quiet.
  "boss-intro"(t) {
    tone(t, 110, 1.4, { wave: "triangle", gain: 0.9, slide: 36, decay: 0.6 })
    noise(t, 0.6, { gain: 0.5, filter: 400 })
    tone(t, "E3", 1.2, { wave: "sawtooth", gain: 0.08, decay: 0.3 })
  },
  // Victory, in C: a leap up, a turn, and a held top note over a walking bass.
  victory(t) {
    const beat = 0.13
    phrase(t, beat, [ [ "C5", 0, 1 ], [ "E5", 1, 1 ], [ "G5", 2, 1 ], [ "C6", 3, 3 ], [ "B5", 6, 1 ], [ "A5", 7, 1 ], [ "B5", 8, 1 ], [ "D6", 9, 1 ], [ "C6", 10, 6 ] ], { gain: 0.3 })
    phrase(t, beat, [ [ "E4", 0, 1 ], [ "G4", 1, 1 ], [ "C5", 2, 1 ], [ "E5", 3, 3 ], [ "G5", 6, 1 ], [ "F5", 7, 1 ], [ "G5", 8, 1 ], [ "F5", 9, 1 ], [ "E5", 10, 6 ] ], { gain: 0.14 })
    phrase(t, beat, [ [ "C3", 0, 3 ], [ "C3", 3, 3 ], [ "G2", 6, 2 ], [ "G2", 8, 2 ], [ "C3", 10, 6 ] ], { wave: "triangle", gain: 0.7 })
  },
  // A place set right: a brass-like call up the chord, answered, and held.
  cleared(t) {
    const beat = 0.14
    phrase(t, beat, [ [ "G4", 0, 1 ], [ "C5", 1, 1 ], [ "E5", 2, 1 ], [ "G5", 3, 3 ], [ "E5", 6, 1 ], [ "G5", 7, 1 ], [ "C6", 8, 8 ] ], { wave: "sawtooth", gain: 0.12 })
    phrase(t, beat, [ [ "E4", 0, 1 ], [ "G4", 1, 1 ], [ "C5", 2, 1 ], [ "E5", 3, 3 ], [ "C5", 6, 1 ], [ "E5", 7, 1 ], [ "G5", 8, 8 ] ], { gain: 0.2 })
    phrase(t, beat, [ [ "C3", 0, 3 ], [ "G2", 3, 3 ], [ "C3", 6, 2 ], [ "C2", 8, 8 ] ], { wave: "triangle", gain: 0.7 })
  },
  // Time's up: a bell tolls three times over a held low chord.
  deadline(t) {
    ;[ 0, 0.55, 1.1 ].forEach((at) => {
      tone(t + at, "A4", 0.9, { wave: "triangle", gain: 0.45, decay: 0.3 })
      tone(t + at, "E5", 0.6, { gain: 0.12, decay: 0.2 })
    })
    ;[ "A2", "E3", "C4" ].forEach((n) => tone(t, n, 2.2, { wave: "sawtooth", gain: 0.06, decay: 0.7 }))
    noise(t, 0.3, { gain: 0.25, filter: 600 })
  },
  // Down and down, and a long low note.
  defeat(t) {
    phrase(t, 0.24, [ [ "E4", 0, 1 ], [ "D4", 1, 1 ], [ "C4", 2, 1 ], [ "B3", 3, 1 ], [ "A3", 4, 4 ] ], { wave: "triangle", gain: 0.6 })
    phrase(t, 0.24, [ [ "A2", 0, 4 ], [ "F2", 4, 4 ] ], { wave: "triangle", gain: 0.4 })
  },
  // Someone awakens: a held low drone, a heartbeat, then a chord that
  // opens upward.
  awakening(t) {
    tone(t, "D2", 2.4, { wave: "sawtooth", gain: 0.08, decay: 0.8 })
    noise(t + 0.2, 0.12, { gain: 0.4, filter: 300 })
    noise(t + 0.5, 0.12, { gain: 0.4, filter: 300 })
    ;[ "D4", "A4", "D5", "F#5", "A5" ].forEach((n, i) => tone(t + 1.1 + i * 0.06, n, 1.4, { wave: "triangle", gain: 0.3, decay: 0.5 }))
    tone(t + 1.1, "D3", 1.6, { wave: "triangle", gain: 0.6, decay: 0.6 })
  },
  // A run up two octaves and a sparkle at the top.
  level_up(t) {
    phrase(t, 0.045, [ "C5", "D5", "E5", "G5", "A5", "C6", "D6", "E6", "G6" ].map((n, i) => [ n, i, 1.2 ]), { gain: 0.22 })
    ;[ "C7", "G6", "E6" ].forEach((n, i) => tone(t + 0.42 + i * 0.03, n, 0.5, { wave: "triangle", gain: 0.3, decay: 0.3 }))
  },
  // A small bell: something is in your hand.
  key(t) {
    tone(t, "B5", 0.5, { wave: "triangle", gain: 0.5, decay: 0.4 })
    tone(t + 0.1, "E6", 0.8, { wave: "triangle", gain: 0.5, decay: 0.4 })
    tone(t + 0.1, "E7", 0.4, { wave: "sine", gain: 0.12, decay: 0.2 })
  },
  // Weight shifting, then the way opens: a thud and a rising fifth.
  door(t) {
    noise(t, 0.35, { gain: 0.5, filter: 300 })
    tone(t, 70, 0.3, { wave: "triangle", gain: 0.7, slide: 45 })
    phrase(t + 0.28, 0.12, [ [ "G3", 0, 1 ], [ "D4", 1, 1 ], [ "G4", 2, 3 ] ], { wave: "triangle", gain: 0.5 })
  },
  // New jobs: a crystal's chime, then the level-up run.
  jobs(t) {
    ;[ "E6", "B6", "E7" ].forEach((n, i) => tone(t + i * 0.12, n, 0.9, { wave: "triangle", gain: 0.25, decay: 0.7 }))
    JINGLES.level_up(t + 0.45)
  },
  treasure(t) {
    phrase(t, 0.07, [ [ "G5", 0, 1 ], [ "C6", 1, 1 ], [ "E6", 2, 1 ], [ "G6", 3, 3 ] ], { gain: 0.2 })
  },
  // Something breaks loose: a rising slide into a held power chord.
  desperation(t) {
    tone(t, "E3", 0.3, { wave: "sawtooth", gain: 0.14, slide: "E4" })
    ;[ "E4", "B4", "E5" ].forEach((n) => tone(t + 0.28, n, 0.9, { wave: "square", gain: 0.12, decay: 0.8 }))
    tone(t + 0.28, "E2", 0.9, { wave: "triangle", gain: 0.7, decay: 0.8 })
    noise(t + 0.28, 0.25, { gain: 0.35, filter: 2500 })
  },
  // One More: a quick stab up an octave, and a hit.
  one_more(t) {
    phrase(t, 0.06, [ [ "A4", 0, 1 ], [ "E5", 1, 1 ], [ "A5", 2, 2 ] ], { wave: "square", gain: 0.12 })
    noise(t, 0.08, { gain: 0.3, filter: 3000 })
  },
  // All-Out Attack: a drum roll into a crash.
  all_out(t) {
    for (let i = 0; i < 8; i++) noise(t + i * 0.06, 0.05, { gain: 0.25 + i * 0.03, filter: 800 })
    ;[ "A3", "E4", "A4", "C#5" ].forEach((n) => tone(t + 0.5, n, 1.0, { wave: "sawtooth", gain: 0.1, decay: 0.8 }))
    noise(t + 0.5, 0.6, { gain: 0.5, filter: 5000 })
  },
  // A check lands: up a fourth and a bright top, or a flat fall.
  check_pass(t) {
    phrase(t, 0.08, [ [ "G5", 0, 1 ], [ "C6", 1, 1 ], [ "E6", 2, 3 ] ], { gain: 0.22 })
    tone(t + 0.16, "C4", 0.4, { wave: "triangle", gain: 0.5 })
  },
  check_fail(t) {
    phrase(t, 0.12, [ [ "E4", 0, 1 ], [ "Eb4", 1, 3 ] ], { wave: "triangle", gain: 0.5 })
    noise(t, 0.12, { gain: 0.2, filter: 600 })
  },
  // The menu's soft confirm.
  blip(t) {
    tone(t, "A5", 0.05, { gain: 0.12, decay: 0.5 })
  }
}

// A phone used as a controller in local co-op stays quiet: the shared
// screen has the sound.
const controller = () => document.body?.dataset.view === "controller"

export function play(name) {
  const jingle = JINGLES[name]
  if (!jingle || muted() || !unlocked || controller()) return
  if (!audio()) return
  jingle(ctx.currentTime + 0.02)
}

// --- music -----------------------------------------------------------------

const music = new Audio()
music.loop = true
music.preload = "auto"
music.volume = 0
music.muted = muted()

let wanted = ""     // the track this page asks for ("" is silence)
let playing = ""    // the track loaded in the element
let held = false    // a boss's moment of silence
let fade = null
let unlocked = false

let cutNext = false // a scene's music step said "cut": no crossfade this once

function fadeTo(volume, done) {
  clearInterval(fade)
  if (cutNext) {
    music.volume = volume
    if (volume > 0) cutNext = false
    return done?.()
  }
  const step = (volume - music.volume) / (FADE_MS / 50)
  if (step === 0) return done?.()
  fade = setInterval(() => {
    const next = music.volume + step
    if ((step > 0 && next >= volume) || (step < 0 && next <= volume)) {
      music.volume = volume
      clearInterval(fade)
      done?.()
    } else {
      music.volume = next
    }
  }, 50)
}

// --- a linked track's player -------------------------------------------------

const EXTERNAL = /^https?:\/\//

function embedBox() { return document.getElementById("music_embed") }

function showEmbed(url) {
  const box = embedBox()
  if (!box) return
  let frame = box.querySelector("iframe")
  if (!frame || frame.dataset.url !== url) {
    box.replaceChildren()
    frame = document.createElement("iframe")
    frame.dataset.url = url
    frame.src = url
    frame.allow = "autoplay; encrypted-media"
    frame.title = "Music"
    frame.referrerPolicy = "strict-origin-when-cross-origin"
    box.append(frame)
  }
  box.classList.toggle("music-embed--spotify", url.includes("spotify.com"))
  box.hidden = false
}

function hideEmbed() {
  const box = embedBox()
  if (!box || box.hidden) return
  box.replaceChildren()
  box.hidden = true
}

function apply() {
  const target = held ? "" : wanted
  if (EXTERNAL.test(target)) {
    // Their player, not ours: the file stops, the embed shows (unless this device is muted).
    if (playing) {
      playing = ""
      fadeTo(0, () => music.pause())
    }
    if (muted()) hideEmbed()
    else showEmbed(target)
    return
  }
  hideEmbed()
  if (target === playing && (!target || !music.paused)) return

  if (!target) {
    playing = ""
    return fadeTo(0, () => music.pause())
  }
  const start = () => {
    if (playing !== target) {
      playing = target
      music.src = target
    }
    if (!unlocked) return
    music.play().then(() => fadeTo(MUSIC_VOLUME)).catch(() => {})
  }
  if (playing && playing !== target && !music.paused) fadeTo(0, start)
  else start()
}

export function setMusic(url, { cut = false } = {}) {
  wanted = controller() ? "" : url || ""
  cutNext = cut
  apply()
  if (!cutNext) return
  // Nothing played or nothing changed: the cut is spent.
  if (!wanted || wanted === playing) cutNext = false
}

// Silence until release, e.g. while a boss's name is on the screen.
export function holdMusic() {
  held = true
  apply()
}

export function releaseMusic() {
  held = false
  apply()
}

// What the page asks for. A battle's music is fixed (the GM can't change it
// mid-fight); elsewhere, the GM's choice holds until they change it back.
function pageMusic() {
  const meta = document.querySelector('meta[name="polychrome-music"]')
  return meta ? meta.content : ""
}

export function followGM({ follow, url, cut = false }) {
  const meta = document.querySelector('meta[name="polychrome-music"]')
  if (!meta || meta.dataset.fixed === "true") return
  meta.content = follow ? meta.dataset.default : url
  setMusic(meta.content, { cut })
}

// A new page starts unheld; its controllers connect (a boss's entrance
// holds the music), then it asks for its track.
document.addEventListener("turbo:before-render", () => { held = false })
document.addEventListener("turbo:load", () => setTimeout(() => setMusic(pageMusic()), 30))

// Nothing sounds until the viewer has done something.
function unlock() {
  if (unlocked) return
  unlocked = true
  audio()
  apply()
}
;[ "pointerdown", "keydown" ].forEach((type) => window.addEventListener(type, unlock, { capture: true, once: true }))

// The soft confirm on game menus (a keyboard choice clicks the item too).
document.addEventListener("click", (event) => {
  if (event.target.closest?.(".pick-table.play .pick-row__act, .button.play")) play("blip")
})
