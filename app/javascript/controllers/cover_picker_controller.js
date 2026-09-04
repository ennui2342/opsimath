import { Controller } from "@hotwired/stimulus"

// Right-click an edition's cover on the book page -> a small panel rolls
// out in place from the cover (not a centered <dialog> — no top-layer
// centering quirks, no backdrop takeover) listing every known cover to
// swap to. Picking one submits straight to EditionMetadataController#update.
export default class extends Controller {
  static targets = ["panel"]

  connect() {
    this.onDocumentClick = (event) => {
      if (this.panelTarget.hidden || this.element.contains(event.target)) return
      this.close()
    }
    this.onKeydown = (event) => { if (event.key === "Escape") this.close() }
    document.addEventListener("click", this.onDocumentClick)
    document.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    document.removeEventListener("click", this.onDocumentClick)
    document.removeEventListener("keydown", this.onKeydown)
  }

  open(event) {
    event.preventDefault()
    event.stopPropagation()
    if (!this.panelTarget.hidden) return

    this.panelTarget.hidden = false
    this.panelTarget.classList.add("scale-95", "opacity-0")
    void this.panelTarget.offsetWidth // force a reflow so the next change transitions, not jumps
    this.panelTarget.classList.remove("scale-95", "opacity-0")
  }

  close() {
    if (this.panelTarget.hidden) return

    this.panelTarget.classList.add("scale-95", "opacity-0")
    setTimeout(() => { this.panelTarget.hidden = true }, 150)
  }
}
