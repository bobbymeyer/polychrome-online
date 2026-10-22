import { Controller } from "@hotwired/stimulus"

// The picture chosen is shown in the art slot at once, before anything is saved (and only here: it is not uploaded
// until the form is).
export default class extends Controller {
  static targets = ["slot"]

  show(event) {
    const file = event.target.files[0]
    if (!file || !file.type.startsWith("image/")) return

    if (this.url) URL.revokeObjectURL(this.url)
    this.url = URL.createObjectURL(file)
    const figure = document.createElement("figure")
    figure.className = "portrait portrait--small"
    const image = document.createElement("img")
    image.src = this.url
    image.alt = "The picture chosen, not yet saved"
    figure.append(image)
    this.slotTarget.replaceChildren(figure)
  }

  disconnect() {
    if (this.url) URL.revokeObjectURL(this.url)
  }
}
