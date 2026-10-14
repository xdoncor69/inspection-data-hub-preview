# Compact Purchase Order directory tables — 2026-10-14

The three Purchase Orders sections retain their existing state grouping and shared search: Drafts (including delivery-first review drafts), Approved for Inspection, POs with Delivery.

Each section now uses a compact read-only table, one order per row, initially ordered:
Delivery No. | PO No. | Customer | Sales team | Status | Actions.

Delivery-only review drafts retain No PO associated, or PO association not recorded for ambiguous legacy imports. Multiple associated delivery numbers remain in one order row. No orders or source lines are merged or deleted.
Open is always directly visible. Draft approval/CSV/deletion retain their original permissions and event handlers under More. The existing details and inspection views are unchanged.

Sales team is read from the already-loaded customer master using clientId. Legacy orders without clientId may use a unique exact normalized customer-name match. Missing/deleted/ambiguous references show Not assigned; no fuzzy match or new customer/team association is inferred. This display does not change stored POs, customers or access permissions.

The existing common table installer supplies mouse/touch drag reorder and edge resizing. Separate layout keys are purchase-order-drafts, purchase-order-approved and purchase-order-delivery; preferences remain local per account and table. No numeric width controls were reintroduced. Colors/styles inherit the three existing skins.

No database changes, data updates or EXE changes. No browser previews or screenshots.
Validation: all 20 inline scripts compile; existing directory search/status/privacy/leading-zero tests adapted to tables; new checks cover 60 rows, six ordered headers, independent layout keys, standalone deliveries, HTML escaping and exact ID/name Sales team resolution. Actual draft and approved render functions were exercised with DOM stubs. No live visual/mobile check.
