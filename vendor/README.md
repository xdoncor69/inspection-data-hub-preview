# Bundled Excel dependencies — Inspection Data Hub

These are **vendored, pinned browser bundles** for the PO / Sales Order import, product import and SAP delivery export. Both copies are served from the application's own GitHub Pages repository. No npm package installation is required by the browser.

| Bundle | Version | SHA-384 Subresource Integrity | Origin |
| --- | --- | --- | --- |
| `sheetjs-0.20.3.full.min.js` | SheetJS CE 0.20.3 | `sha384-EnyY0/GSHQGSxSgMwaIPzSESbqoOLSexfnSMN2AP+39Ckmn92stwABZynq1JyzdT` | [Official SheetJS CDN](https://cdn.sheetjs.com/xlsx-0.20.3/package/dist/xlsx.full.min.js) |
| `exceljs-hardened-5.0.0.min.js` | exceljs-hardened 5.0.0 | `sha384-6yvA6DF5pib8afXuAOKT4TLXI62psTCPbhNQpZymQQ9eaGpLC9c8KZ2SaFtniJV6` | [Published npm package via jsDelivr](https://cdn.jsdelivr.net/npm/exceljs-hardened@5.0.0/dist/exceljs.min.js) |

**Trust distinction:** ExcelJS Hardened is an **unofficial security-maintained fork** of ExcelJS, not an official upstream ExcelJS release. The original ExcelJS 4.4.0 bundle and the old `xlsx-js-style@1.2.0` bundle are intentionally not included.

Licensing and notices:
- SheetJS CE: Apache-2.0; [license](./LICENSE-sheetjs.txt).
- ExcelJS Hardened: MIT; [license](./LICENSE-exceljs-hardened.txt).

Version updates require re-auditing upstream advisories, downloading a pinned official package artifact, recalculating SHA-384, passing the offline regression tests, and synchronizing `preview/vendor/` (private) with `vendor/` (public). Never replace these bundles with an unpinned `latest` URL.

The browser loaders compare the exact SheetJS version and use `integrity` attributes with `crossOrigin=anonymous`. The loader for the styled writer is separate and does **not** replace `window.XLSX`. ZIP expansion / file size and row/column bounds are enforced before and during parsing.
