# Purchase Order directory search — 2026-10-14

The shared Purchase Orders search now matches PO number, delivery number and customer name. Every draft/approved result displays the PO reference (when present), associated delivery number(s), customer and an explicit status pill before opening the order.

Statuses follow existing records: Draft · pending inspection; Approved for Inspection; Delivery available. No Closed state is invented: the current schema has no persisted closure flag or closure action. Export/download is not treated as closure.

## Identity
- PO only: PO number + customer + status.
- PO with deliveries: PO number + all associated delivery numbers + customer + status.
- Delivery-first intake explicitly created without a supplied PO: No PO associated + delivery number + customer + draft/approved status. The internal generated review PO is retained unchanged.
- A legacy intake with a generated-looking reference and a null has_supplied_po flag displays PO association not recorded. That ambiguity is not rewritten as known absence or presence.
- If an administrator has replaced an intake's generated reference with a distinct PO number, the current PO reference is displayed.
- Leading zeros remain intact. Partial searches filter existing identities without approximating or joining documents by matching numbers alone.

## Safe metadata
Migration safe_order_directory_delivery_metadata adds inspection_internal.read_order_directory() and authenticated public wrapper inspection_read_order_directory(). It returns only whitelisted delivery IDs/numbers/approved associations and intake IDs/draft associations/numbers/customer/has_supplied_po. JSON aggregation avoids REST row-limit truncation.
Shared-draft intake summaries are readable by all signed-in users who can consult those drafts. Raw intake rows/files keep their existing owner/admin policies. Approved delivery metadata follows existing approved-order access. No physical observations, line evidence, photos, source rows, authorship or snapshots are added to this directory API.
The functions require login, have a fixed empty search_path and explicitly revoked anonymous/PUBLIC execution. No existing RLS policy was loosened; no business records changed.

## Refresh
Metadata is loaded with the existing order state, reused during typing and included in the existing 15-second change comparison. There is no network call per keystroke. Saving a delivery immediately updates its order metadata. Query failures preserve the existing connection/error behavior; failed metadata loads do not silently become empty results.
Metadata is cleared on logout. Existing source-file permissions, export logic, physical evidence privacy, three skins and web-only scope remain unchanged.

## Checks
20 inline scripts compile. Node tests cover all three stages, PO-only, attached/standalone/multiple deliveries, leading zeros, customer search, legacy ambiguity, escaping, unchanged source objects and actual draft/approved result rendering with DOM stubs. No browser, screenshot or rendered preview was used.
Authenticated-role SQL checks for David and Ariadna passed, with strict field whitelists and anonymous execution denied. The new metadata RPC contains no inspection evidence. Existing anonymous/owner/raw-file protections remain in place.
No new visual/mobile browser check was performed, per user preference.

Files: database/order-directory-metadata.sql (applied migration reference; do not rerun blindly), tests/order-directory-search.cjs, tests/order-directory-metadata.sql.
