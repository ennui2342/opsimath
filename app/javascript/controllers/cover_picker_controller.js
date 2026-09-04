import { Controller } from "@hotwired/stimulus"

// Right-click an edition's cover on the book page -> a modal listing every
// known cover (one per source that has one on file) to swap it quickly,
// without leaving the page for the full reconcile-edition screen. Picking
// one submits straight to EditionMetadataController#update.
export default class extends Controller {
  static targets = ["dialog"]

  open(event) {
    event.preventDefault()
    this.dialogTarget.showModal()
  }

  connect() {
    this.onBackdropClick = (event) => {
      if (event.target === this.dialogTarget) this.close()
    }
    this.dialogTarget?.addEventListener("click", this.onBackdropClick)
  }

  disconnect() {
    this.dialogTarget?.removeEventListener("click", this.onBackdropClick)
  }

  close() {
    this.dialogTarget.close()
  }
}
