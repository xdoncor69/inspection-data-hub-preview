# Product field simplification — 2026-10-14

Web only; no EXE update. No screenshots, rendered previews or browser sessions were used.

## Current fields
Item identifier, description, brand, class (Meat / Poultry), product family, Pack / Size, EST.
Pack / Size uses the existing `pack` key. Legacy `pack` and `size` values are joined with " · ", preserving literal units and distinct components. Exact case-insensitive duplicate components are included once; no arithmetic or conversion.
Both importer mappings may accept an additional source size column, but only one combined catalog field is saved. Supplier/producer and sales-unit source columns are no longer collected or inferred as brand/size.

## Dormant type
Dairy data and internal recognition remain in the code. No Dairy navigation, class choice or Plant Number label is shown. Product Search excludes the dormant type. Class display suppression does not rewrite stored PO snapshots. Existing brand rules for the dormant type are preserved when other brand rules are edited.

## Storage update
A data-only SQL update was applied to the official master catalog (revision 29). No database schema migration was applied. The attempted schema migration calls failed before execution with Invalid or expired requestState; the final implementation needs no new tables, functions, triggers or grants.
454 product identifiers retained; 373 combined Pack / Size values. No `producer`, `salesUnit` or separate `size` keys remain in the current master catalog.
Only pack/size/producer/salesUnit changed. The actual administrator identity and real time were recorded by the existing audit trigger.
Approved POs, deliveries, all workspaces, the 467 initial validations and other official domains were checked unchanged inside the transaction.
The cleanup is idempotent and retained historical field values in the existing administrator audit.
`database/compact-product-data.sql` records the applied data operation. Inspect current state before any future execution.

Current catalog JSON text: 98,719 -> 74,762 bytes (~24.3% smaller). This is master JSON size, not total physical database/storage reduction. Audit/history is retained; no vacuum or historical deletion was performed.
Historical documents/source files may still contain old fields as originally recorded. New imports/catalog saves use the reduced schema. Previously opened app tabs should reload.

## Retained
Product notes and brand notes in their separate domains; photos; EST references/trends; fixed EST and stability rules; initial-review reasons; administrative validations; authentic physical observations and authorship; upload-date references and derived statistics. No fabricated inspection/receipt data.
Initial-review reasons explain a first-inspection priority; they remain separate from administrative validation and are superseded by real observation data.

## Validation
- All 19 inline scripts compile.
- Node tests: combined pack/size, literal units, zero/blank values, preserved leading-zero identifiers, nonmutation of source objects, idempotence, legacy source-column parsing and ignored retired fields.
- HTML structure: profile controls removed (not CSS-hidden); column/header alignment (10 Product Search, 13 Invoice Overview); no duplicate IDs or visible Dairy/Plant Number/Sales Unit/Supplier Group labels.
- Authenticated-role SQL checks: David and Ariadna each read all 454 simplified catalog products; zero retired fields.
- Database transaction assertions preserved unrelated official domains, approved POs, deliveries, workspaces and validation records.
- Three skins and table resize/reorder code retained.
- No visual/mobile rendering checks were run, per user instruction.
