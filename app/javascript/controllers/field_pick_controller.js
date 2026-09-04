import { Controller } from "@hotwired/stimulus"

// Edition-metadata screen: N source cards, each field pickable from any of
// them, but at most one source per field — checking "publisher" on the
// ISFDB card should drop any "publisher" pick already ticked on the
// Goodreads card. Checkbox values are self-describing ("<provider>:<field>"
// — see Ui::ComparisonCardComponent's field_value_prefix), so the field
// name is just the part after the colon; no per-card wiring needed.
export default class extends Controller {
  static targets = ["box"]

  pick(event) {
    const box = event.target
    if (!box.checked) return

    const field = box.value.split(":").pop()
    for (const other of this.boxTargets) {
      if (other !== box && other.value.split(":").pop() === field) other.checked = false
    }
  }
}
