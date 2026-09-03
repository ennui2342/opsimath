import { Controller } from "@hotwired/stimulus"

// Keyboard-first review, per docs/UI_PRINCIPLES.md principle 3 — the
// review queue's whole job is fast, repeated decisions, so accept/reject
// are keypresses, not just click targets. Bound to `keydown` on the
// document (not just this element) so focus position never matters —
// exactly the point of a triage screen.
export default class extends Controller {
  static targets = ["accept", "reject"]

  connect() {
    this.onKeydown = this.onKeydown.bind(this)
    document.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
  }

  onKeydown(event) {
    if (event.metaKey || event.ctrlKey || event.altKey) return
    if (this.isTypingTarget(event.target)) return

    if (event.key === "a" || event.key === "A") {
      event.preventDefault()
      this.acceptTarget.requestSubmit()
    } else if (event.key === "r" || event.key === "R") {
      event.preventDefault()
      this.rejectTarget.requestSubmit()
    }
  }

  isTypingTarget(element) {
    const tag = element.tagName
    return tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || element.isContentEditable
  }
}
