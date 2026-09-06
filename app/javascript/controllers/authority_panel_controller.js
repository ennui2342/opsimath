import { Controller } from "@hotwired/stimulus"

// The "same publisher?" roll-out panel on an enrichment_conflict's
// publisher row. It can't be a real <form> (the whole review screen is
// already one, and forms don't nest), so the submit posts via fetch and
// hands the Turbo Stream response back to Turbo — same net effect as a
// data-turbo-stream form. Opens in place, closes on outside-click / Esc,
// like cover_picker. On open (and whenever the preferred choice changes)
// it fetches a dry-run of what establishing the term would rewrite, so an
// over-broad mapping is visible before you commit.
export default class extends Controller {
  static targets = ["panel", "choice", "otherRadio", "otherInput", "preview"]
  static values = { url: String, previewUrl: String, decision: String, current: String, proposed: String }

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
    if (!this.panelTarget.hidden) this.refreshPreview()
  }

  close() {
    this.panelTarget.hidden = true
  }

  pickOther() {
    if (this.hasOtherRadioTarget) this.otherRadioTarget.checked = true
  }

  chosenPreferred() {
    const value = this.choiceTargets.find((c) => c.checked)?.value
    return value === "__other__" ? this.otherInputTarget.value.trim() : value
  }

  variants() {
    return [this.currentValue, this.proposedValue]
  }

  async refreshPreview() {
    const preferred = this.chosenPreferred()
    if (!preferred) {
      this.previewTarget.textContent = ""
      return
    }
    const params = new URLSearchParams({ preferred_label: preferred })
    this.variants().forEach((v) => params.append("variant_labels[]", v))

    try {
      const response = await fetch(`${this.previewUrlValue}?${params}`, { headers: { Accept: "application/json" } })
      if (!response.ok) return
      const p = await response.json()
      if (p.rewritten === 0) {
        this.previewTarget.textContent = "No catalogued edition uses a variant — nothing would be rewritten."
      } else {
        const bits = [`${p.corroborated} match ISFDB`]
        if (p.contradicted) bits.push(`${p.contradicted} ISFDB names another`)
        if (p.unmatched) bits.push(`${p.unmatched} not in ISFDB`)
        this.previewTarget.textContent = `Would rewrite ${p.rewritten} edition${p.rewritten === 1 ? "" : "s"}: ${bits.join(", ")}.`
      }
      this.previewTarget.classList.toggle("text-amber-700", p.risky)
      this.previewTarget.classList.toggle("dark:text-amber-400", p.risky)
      this.previewTarget.classList.toggle("text-gray-500", !p.risky)
    } catch (e) {
      /* preview is advisory — a failed fetch just leaves it blank */
    }
  }

  async submit(event) {
    event.preventDefault()
    const preferred = this.chosenPreferred()
    if (!preferred) return

    const body = new URLSearchParams()
    body.append("preferred_label", preferred)
    this.variants().forEach((v) => body.append("variant_labels[]", v))
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
