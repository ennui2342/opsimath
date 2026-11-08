import { Controller } from "@hotwired/stimulus"

// Scan a book's barcode into a search box and submit it (docs/CATALOG.md,
// "Add a book", "Scanning US mass-markets") — the web app's twin of the
// pocket app's scanner; both read through app/assets/mobile/scan.js
// (zxing-cpp in WebAssembly, loaded on first use). An EAN-13 is the ISBN.
// A US mass-market's retail UPC names only publisher and price: with its
// 5-digit add-on it's searched as "UPC add-on" (UpcLookup) — put in the box
// first for the add-on to be checked against the printed digits, since it
// can read wrong; if the camera gets the UPC but not the add-on in a few
// seconds, the UPC alone goes in the box for the five digits to be typed.
//
// Browsers only offer the camera to a secure page, so on the plain-HTTP
// internal address the button instead goes to the same page on the HTTPS
// one (`secureUrl`), which opens the scanner on arrival.
const ADD_ON_WAIT = 12 // polls (~3s) to wait for an add-on after a bare UPC

export default class extends Controller {
  static targets = ["input", "button", "overlay", "video", "hint", "check"]
  static values = { secureUrl: String, autostart: Boolean, scripts: Array, wasmUrl: String }

  connect() {
    this.supported = window.isSecureContext && !!navigator.mediaDevices && typeof WebAssembly === "object"
    this.redirect = !window.isSecureContext && this.secureUrlValue.startsWith("https:")
    this.buttonTarget.hidden = !(this.supported || this.redirect)
    if (this.supported && this.autostartValue) this.open()
  }

  disconnect() { this.close() }

  async open() {
    if (!this.supported) {
      if (this.redirect) window.location.href = this.secureUrlValue
      return
    }
    try {
      await this.loadScanner()
      this.stream = await navigator.mediaDevices.getUserMedia(window.OpsimathScan.CAMERA)
      this.videoTarget.srcObject = this.stream
      await this.videoTarget.play()
      this.overlayTarget.hidden = false
      this.hintTarget.textContent = "Point at the barcode"
      this.upc = null
      this.confirm = window.OpsimathScan.confirmer()
      this.poll = setInterval(() => this.detect(), 250)
    } catch (e) {
      this.close()
      this.inputTarget.placeholder = e && e.name === "NotAllowedError" ? "Camera permission denied" : "Camera unavailable"
    }
  }

  async loadScanner() {
    if (!window.OpsimathScan) {
      for (const src of this.scriptsValue) {
        await new Promise((resolve, reject) => {
          const s = document.createElement("script")
          s.src = src
          s.onload = resolve
          s.onerror = reject
          document.head.appendChild(s)
        })
      }
    }
    window.OpsimathScan.prepare(this.wasmUrlValue)
  }

  async detect() {
    if (this.busy || this.overlayTarget.hidden || !this.videoTarget.videoWidth) return
    this.busy = true
    try {
      const code = window.OpsimathScan.interpret(await window.OpsimathScan.readFrame(this.videoTarget))
      const confirmed = this.confirm(code)
      if (confirmed?.kind === "isbn") return this.submit(confirmed.isbn)
      // The add-on is read wrong too often to search on unchecked (Beggars
      // and Choosers: 55010 read as 25011 on every try, 2026-11-08): it goes
      // in the box to be checked against the printed digits first.
      if (confirmed?.kind === "upc") return this.fillForCheck(`${confirmed.upc} ${confirmed.addOn}`)
      if (code?.kind === "upc") {
        this.upc ||= { code: code.upc, polls: 0 }
        this.hintTarget.textContent = "A US retail UPC — hold steady to read the small barcode beside it too"
      }
      if (this.upc && ++this.upc.polls > ADD_ON_WAIT) this.fillForCheck(`${this.upc.code} `)
    } catch (_) {
      // transient decode errors are normal
    } finally {
      this.busy = false
    }
  }

  // A UPC into the box, with the add-on as read (if it was) for Mark to
  // check against the five digits printed over the small barcode — or type
  // — before searching.
  fillForCheck(value) {
    this.close()
    this.inputTarget.value = value
    this.inputTarget.focus()
    this.inputTarget.setSelectionRange(value.length, value.length)
    if (this.hasHintTarget) this.hintTarget.textContent = ""
    this.checkTarget.hidden = false
  }

  submit(value) {
    this.close()
    this.inputTarget.value = value
    this.inputTarget.form.requestSubmit()
  }

  close() {
    if (this.hasOverlayTarget) this.overlayTarget.hidden = true
    clearInterval(this.poll)
    this.stream?.getTracks().forEach((t) => t.stop())
    this.stream = null
  }
}
