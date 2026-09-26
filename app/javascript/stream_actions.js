// Custom Turbo Stream actions.
//
// reload_frame: reload one Turbo Frame in place. The asset pipeline (§8)
// sends it as each generated image lands, so only the art section updates
// and the rest of the page, a half-typed form included, is left alone.
const { StreamActions } = window.Turbo

StreamActions.reload_frame = function () {
  const frame = document.getElementById(this.target)
  if (!frame) return
  if (frame.src) frame.reload()
  else frame.src = frame.dataset.src
}
