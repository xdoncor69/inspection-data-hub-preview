# Purchase Orders import dialogs

Purchase Orders now starts with two compact actions: Import PO and Delivery First. The Import Order sidebar entry is removed; legacy internal meat routes resolve to Purchase Orders.

Import PO uses the existing PO form inside an accessible native dialog, with customer selection, source-column mapping, the current-file overview, Import again and Move to Drafts. Opening starts clean. Cancel or Escape invalidates unfinished reads and clears the form. Successful draft creation closes it; failed persistence leaves the current import available. Duplicate PO selection closes the import dialog before the existing choice window: opening an existing order never applies imported rows, while choosing another number reopens the retained current-file form.

Delivery First directly opens the existing delivery import dialog. No extra landing panel or document directory is inserted between the action and its form.

The import parsers, catalog matching, source fields, delivery writer, pending-send protections and database permissions are unchanged. Dialog styling reuses the active skin and constrains width/height to the viewport; wide overview tables scroll within their container.

Validation: all 20 inline scripts compile; HTML contains unique IDs, both launch buttons belong to Purchase Orders, and the PO file input is inside its dialog. Code-only tests cover entry permission, cancel, duplicate handoff/reopen, failed persistence retention, successful draft handoff, leading-zero identifiers and source-field preservation. No browser session, screenshots or visual preview used. Run node tests/purchase-order-import-dialog.cjs preview/index.html (public repository: index.html).
