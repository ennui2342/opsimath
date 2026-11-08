// Barcode reading for both scanners — the web app's (barcode_scan_controller)
// and the pocket app's (pocket.js) — so they read the same things the same
// way (docs/CATALOG.md, "Scanning US mass-markets"). zxing-cpp compiled to
// WebAssembly (zxing_reader.js / .wasm, zxing-wasm 3.1.6, served from our
// own assets so the pocket app scans offline), not the browser's
// BarcodeDetector: that can't read the 5-digit add-on beside a US
// mass-market's retail UPC, which is the only part of it that identifies
// the book — and it doesn't exist at all in Safari.
//
// Read as UPC-A through the EAN-13 reader, a UPC comes back as 13 digits
// with a leading 0; the add-on is reported apart, in `extra`.
(function () {
  let prepared = false;
  let canvas = null;

  function prepare(wasmUrl) {
    if (prepared) return;
    window.ZXingWASM.prepareZXingModule({
      overrides: { locateFile: (path, prefix) => (path.endsWith(".wasm") ? wasmUrl : prefix + path) },
    });
    prepared = true;
  }

  // One video frame -> zxing results.
  async function readFrame(video) {
    canvas = canvas || document.createElement("canvas");
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    const ctx = canvas.getContext("2d", { willReadFrequently: true });
    ctx.drawImage(video, 0, 0);
    const image = ctx.getImageData(0, 0, canvas.width, canvas.height);
    return window.ZXingWASM.readBarcodes(image, {
      formats: ["EAN13", "UPCA"], eanAddOnSymbol: "Read", tryHarder: true, maxNumberOfSymbols: 2,
    });
  }

  function addOnOf(result) {
    try {
      const addOn = JSON.parse(result.extra || "{}").EanAddOn;
      return /^\d{5}$/.test(addOn || "") ? addOn : null;
    } catch (_) {
      return null;
    }
  }

  // zxing results -> { kind: "isbn", isbn } | { kind: "upc", upc, addOn } | null.
  // An ISBN wins; a UPC read with its add-on beats one without.
  function interpret(results) {
    let upc = null;
    for (const r of results || []) {
      const code = (r.text || "").slice(0, 13);
      if (/^97[89]\d{10}$/.test(code)) return { kind: "isbn", isbn: code };
      const digits = /^0\d{12}$/.test(code) ? code.slice(1) : (/^\d{12}$/.test(r.text || "") ? r.text : null);
      if (digits) {
        const addOn = addOnOf(r);
        if (!upc || (addOn && !upc.addOn)) upc = { kind: "upc", upc: digits, addOn };
      }
    }
    return upc;
  }

  // Add-ons misread now and then (25011 for 55010, 2026-11-08), so one is
  // trusted only once the same five digits have been read twice. Fed each
  // frame's interpretation; -> the code to act on, or null to keep looking.
  function confirmer() {
    const seen = {};
    return function (code) {
      if (!code || code.kind === "isbn" || !code.addOn) return code && code.kind === "isbn" ? code : null;
      const key = code.upc + " " + code.addOn;
      seen[key] = (seen[key] || 0) + 1;
      return seen[key] >= 2 ? code : null;
    };
  }

  window.OpsimathScan = { prepare, readFrame, interpret, confirmer };
})();
