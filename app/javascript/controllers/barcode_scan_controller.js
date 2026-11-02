import { Controller } from "@hotwired/stimulus"

// Scan a book's barcode into a search box and submit it (docs/CATALOG.md,
// "Add a book") — the shop-lookup PWA's scanner (app/assets/mobile/
// pocket.js) for the web app. Uses the browser's own BarcodeDetector, so
// the button only appears where there is one (Chrome on Android and
// macOS; not Safari) and over HTTPS. An EAN-13 is the ISBN; a 12-digit
// UPC (some US mass-markets) isn't one, so it asks for the ISBN typed.
export default class extends Controller {
  static targets = ["input", "button", "overlay", "video", "hint"]

  connect() {
    this.supported = "BarcodeDetector" in window && !!navigator.mediaDevices
    this.buttonTarget.hidden = !this.supported
  }

  disconnect() { this.close() }

  async open() {
    try {
      this.detector ||= new window.BarcodeDetector({ formats: ["ean_13", "upc_a"] })
      this.stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" } })
      this.videoTarget.srcObject = this.stream
      await this.videoTarget.play()
      this.overlayTarget.hidden = false
      this.hintTarget.textContent = "Point at the barcode"
      this.poll = setInterval(() => this.detect(), 250)
    } catch (e) {
      this.close()
      this.inputTarget.placeholder = e && e.name === "NotAllowedError" ? "Camera permission denied" : "Camera unavailable"
    }
  }

  async detect() {
    if (this.busy || this.overlayTarget.hidden || !this.videoTarget.videoWidth) return
    this.busy = true
    try {
      const values = (await this.detector.detect(this.videoTarget)).map((c) => c.rawValue)
      const ean = values.find((v) => /^\d{13}$/.test(v))
      if (ean) {
        this.close()
        this.inputTarget.value = ean
        this.inputTarget.form.requestSubmit()
      } else if (values.some((v) => /^\d{12}$/.test(v))) {
        this.hintTarget.textContent = "That's a UPC, not an ISBN — type the ISBN from the cover"
      }
    } catch (_) {
      // transient decode errors are normal
    } finally {
      this.busy = false
    }
  }

  close() {
    if (this.hasOverlayTarget) this.overlayTarget.hidden = true
    clearInterval(this.poll)
    this.stream?.getTracks().forEach((t) => t.stop())
    this.stream = null
  }
}
