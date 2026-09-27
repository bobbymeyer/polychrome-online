// Custom Turbo Stream actions.
//
// reload_frame: reload one Turbo Frame in place. The asset pipeline (§8)
// sends it as each generated image lands, so only the art section updates
// and the rest of the page, a half-typed form included, is left alone.
//
// battle_start: a battle began in this campaign; everyone goes to it
// (stage.js plays the transition).
//
// music: the GM changed the table's music (sound.js).
import { toBattle } from "stage"
import { followGM } from "sound"

const { StreamActions } = window.Turbo

StreamActions.battle_start = function () {
  toBattle(this.getAttribute("url"), { boss: this.getAttribute("boss") === "true" })
}

StreamActions.music = function () {
  followGM({ follow: this.getAttribute("follow") === "true", url: this.getAttribute("url") || "" })
}

StreamActions.reload_frame = function () {
  const frame = document.getElementById(this.target)
  if (!frame) return
  if (frame.src) frame.reload()
  else frame.src = frame.dataset.src
}
