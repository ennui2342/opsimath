import { Controller } from "@hotwired/stimulus"

// "Select all" / "Clear all" for a set of checkboxes (bargain hunting's
// cover picker): ticks or unticks every checkbox inside the element.
export default class extends Controller {
  all() { this.set(true) }

  none() { this.set(false) }

  set(checked) {
    this.element.querySelectorAll("input[type=checkbox]").forEach((box) => {
      if (box.checked !== checked) {
        box.checked = checked
        box.dispatchEvent(new Event("change", { bubbles: true }))
      }
    })
  }
}
