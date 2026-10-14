# Direct table adjustment — 2026-10-14

The approved PO detail heading and print heading now read PO [number] - Approved for Inspection, preserving the existing styling.

The shared table-layout installer no longer creates Reset columns, the column selector, left/right buttons, Width (px) or Apply width. Their handlers and unused form CSS were removed structurally across all tables. The short drag instruction remains.
Mouse header drag/drop and edge resizing are retained. Touch/pen dragging on the header grip now uses Pointer Events and pointer capture, with a drop-target outline and horizontal container edge scrolling. Cancelled or unrelated pointer events do not commit a reorder.
Keyboard adjustment on the actual header grip/resize handle remains available.
Stored widths and order keep the same account/table preference keys. No catalog, PO, delivery, database, evidence or export data changed. No EXE update.

Validation: modified table and approved-detail functions compile; tests cover heading format, form-control removal, touch/pen drop and cancellation, pointer isolation, preserved mouse handling and per-account preference save/restore. No browser, screenshots or rendered previews were used. Physical-device behavior was not visually tested.
