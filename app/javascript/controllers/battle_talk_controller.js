import { Controller } from "@hotwired/stimulus"

// Talk as an action in battle (battles/panels/_player): the Talk row of the
// command menu opens the page's composer (a <details> under the field) and
// puts the cursor in it, so saying something is one press, like any command.
export default class extends Controller {
  open(event) {
    event.preventDefault()
    const box = document.querySelector("details.battle-composer")
    if (!box) return
    box.open = true
    box.scrollIntoView({ block: "nearest", behavior: "smooth" })
    const focus = () => box.querySelector("textarea")?.focus({ preventScroll: true })
    if (box.querySelector("textarea")) focus()
    else box.addEventListener("turbo:frame-load", focus, { once: true })
  }
}
