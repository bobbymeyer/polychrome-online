// What a refresh by morphing leaves alone (docs/HANDOFF.md §10: the table
// fetches itself again and is morphed in place, Campaign::Broadcasts).
//
// The server renders each element as it starts; some of its attributes are
// then the page's own: a view picked, a drawer opened, a choice revealed, the
// stage's fitted size. An element lists those in data-morph-keep and a
// morph doesn't put them back. A <details> or <dialog> keeps whether it's
// open, whoever opened it, and a stream keeps saying it's connected.
//
// Whole elements the page owns (the dialogue box, the log, the composer, a
// card that's up) are data-turbo-permanent, and so is anything a script adds
// to the page for a moment (a toast, a roll), so a morph doesn't take it away.

document.addEventListener("turbo:before-morph-attribute", (event) => {
  const { attributeName } = event.detail
  const el = event.target
  const kept = el.dataset?.morphKeep?.split(/\s+/) || []
  if (kept.includes(attributeName) ||
      (attributeName === "open" && el.matches?.("details, dialog")) ||
      (attributeName === "connected" && el.localName === "turbo-cable-stream-source")) event.preventDefault()
})
