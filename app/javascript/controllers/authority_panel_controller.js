import { Controller } from "@hotwired/stimulus"

// The "same publisher?" roll-out panel on an enrichment_conflict's
// publisher row. It can't be a real <form> (the whole review screen is
// already one, and forms don't nest), so the submit posts via fetch and
// hands the Turbo Stream response back to Turbo — same net effect as a
// data-turbo-stream form. Opens in place, closes on outside-click / Esc,
// like cover_picker.
export default class extends Controller {
  static targets = ["panel", "choice", "otherRadio", "otherInput"]
  static values = { url: String, decision: String, current: String, proposed: String }

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

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    this.panelTarget.hidden = !this.panelTarget.hidden
  }

  close() {
    this.panelTarget.hidden = true
  }

  pickOther() {
    if (this.hasOtherRadioTarget) this.otherRadioTarget.checked = true
  }

  async submit(event) {
    event.preventDefault()
    const chosen = this.choiceTargets.find((c) => c.checked)?.value
    const preferred = chosen === "__other__" ? this.otherInputTarget.value.trim() : chosen
    if (!preferred) return

    const body = new URLSearchParams()
    body.append("preferred_label", preferred)
    body.append("variant_labels[]", this.currentValue)
    body.append("variant_labels[]", this.proposedValue)
    body.append("from_decision_id", this.decisionValue)

    const token = document.querySelector('meta[name="csrf-token"]')?.content
    const response = await fetch(this.urlValue, {
      method: "POST",
      headers: { "X-CSRF-Token": token, Accept: "text/vnd.turbo-stream.html" },
      body
    })
    if (response.ok) window.Turbo.renderStreamMessage(await response.text())
    this.close()
  }
}
