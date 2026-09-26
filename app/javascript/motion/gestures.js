// The motion vocabulary (docs/HANDOFF.md §3.2): whole-element transforms only,
// as anime.js tween presets. Battle and UI chrome use the same set, so the
// whole app moves the same way.
//
// Each preset is a function of the facing direction (1 = toward the right).
export const GESTURES = {
  bounce: () => ({ translateY: [0, -14, 0], duration: 360, ease: "outQuad" }),
  shake: () => ({ translateX: [0, -9, 9, -6, 6, -3, 0], duration: 420, ease: "linear" }),
  flash: () => ({ opacity: [1, 0.2, 1, 0.2, 1], duration: 420, ease: "linear" }),
  fade: () => ({ opacity: [1, 0.3], duration: 450, ease: "outQuad" }),
  spin: () => ({ rotate: [0, 360], duration: 500, ease: "inOutQuad" }),
  lunge: (dir) => ({ translateX: [0, 32 * dir, 0], duration: 360, ease: "inOutQuad" }),
  pop: () => ({ scale: [0.6, 1.15, 1], opacity: [0.4, 1, 1], duration: 380, ease: "outBack" }),
  float: () => ({ translateY: [0, -12, 0], duration: 600, ease: "inOutSine" }),
  tint: () => ({ filter: ["hue-rotate(0deg) saturate(1)", "hue-rotate(140deg) saturate(2)", "hue-rotate(0deg) saturate(1)"], duration: 520, ease: "linear" }),
  slide: (dir) => ({ translateX: [0, 90 * dir], opacity: [1, 0], duration: 520, ease: "inQuad" })
}

export function gestureDuration(name) {
  return (GESTURES[name] || GESTURES.flash)(1).duration
}

// Add a gesture for `element` to `timeline` at `at` ms. Returns its duration.
export function gesture(timeline, element, name, at, direction = 1) {
  const params = (GESTURES[name] || GESTURES.flash)(direction)
  if (element) timeline.add(element, params, at)
  return params.duration
}
