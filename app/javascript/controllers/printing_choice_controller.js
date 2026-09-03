import { Controller } from "@hotwired/stimulus"

// enrichment_printing_choice review: N ISFDB-printing cards, each with a
// radio in its header and per-field checkboxes inside. Only the picked
// card's checkboxes are live — the others are disabled (so the form never
// submits fields from a printing you didn't choose) and dimmed. Switching
// the radio re-checks every field on the newly-picked card, matching the
// server-rendered default (card 0 all-checked).
export default class extends Controller {
  static targets = ["card"]

  connect() {
    this.activeKey = null
    this.sync()
  }

  sync() {
    const activeCard = this.cardTargets.find(
      (c) => c.querySelector("input[type=radio]")?.checked
    )
    const activeKey = activeCard?.dataset.printingChoiceKey
    const switched = activeKey !== this.activeKey
    this.activeKey = activeKey

    for (const card of this.cardTargets) {
      const active = card === activeCard
      card.classList.toggle("opacity-50", !active)
      for (const box of card.querySelectorAll("input[type=checkbox]")) {
        box.disabled = !active
        if (switched) box.checked = active
      }
    }
  }
}
