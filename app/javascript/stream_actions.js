// Custom Turbo Stream actions.
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

// battle_panel: something changed that every seat's panel should show (a player back): each asks for its own.
StreamActions.battle_panel = function () {
  window.dispatchEvent(new CustomEvent("battle-panel:changed"))
}

StreamActions.music = function () {
  followGM({ follow: this.getAttribute("follow") === "true", url: this.getAttribute("url") || "", cut: this.getAttribute("cut") === "true" })
}
