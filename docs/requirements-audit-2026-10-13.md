# Inspection Data Hub requirements audit — 2026-10-13

Scope: existing web app, master requirements 1–22 and subsequent requests in this conversation. No executable update. No historical observations or PO contents changed by this audit.

## Evidence and limits

- Both repositories initially had HTML blob 3c9bd5139fab7d5c09b13ee81c6514cc4b62b035; live Pages had been verified against that blob.
- Authenticated browser checks: David administrator, 454 catalog Items; exact lookup 112362 shows separate initial validations for 471 and 81B and no receipt recorded; global exact lookup 110790-631 and 112362 returns both; Settings exposes initialization.
- Current live database checks: David is sole administrator; Ariadna is normal. No Invitados account or profile exists. Other existing accounts retained.
- SQL as authenticated Ariadna: 454 catalog Items, 467 initial validations, no other-user workspace rows, no direct SELECT on private PO/delivery snapshots or official records, no physical-evidence fields in the approved-PO RPC response.
- Legacy request/review RPCs have no authenticated or anonymous EXECUTE. Storage buckets are private. Client and workspace grants/policies inspected.
- Current tests: embedded script syntax; catalog refresh revision/race/account/unsaved-edit protection; export fixed columns, preserved lb/kg units, zero-quantity exclusion, blank quantities, leading-zero identifiers, filename, three blank rows and quantity total.
- Prior UI/import/delivery/security tests are recorded in conversation history, but this audit does not claim they were all rerun live.
- Mobile end-to-end and all three skins need a new visual regression pass after the latest changes. Normal-user live browser testing was not repeated in this pass (SQL role checks were).
- Supabase advisor: existing leaked-password-protection warning remains; not changed.

## Requirement coverage

“Present” means corresponding implementation was found in the current source/schema, not that every possible scenario passed a new end-to-end test.

| Requirements | Current implementation / evidence |
| --- | --- |
| 1 Existing repositories, web only | Incremental identical HTML changes in private preview/index.html and public index.html; no EXE changes. |
| 2 Order workflow | Private PO preparation, inspection, approval, associated independent delivery and export present. No SAP/PHIS/email integration. |
| 3 Online DB / interrupted sends | Official Supabase reads; account-bound IndexedDB pending jobs, idempotent operation IDs, retry/conflict handling and separate never-connected/interrupted states present. |
| 4 Accounts | David sole admin, Ariadna normal. Shared-account label workflow present. Invitados account still absent; user must supply its chosen identity securely. |
| 5 Evidence privacy | Public safe RPCs and private-column grants inspected/tested; only administrator receives full official observations and snapshots. |
| 6 Retired change requests | Mutating request/review RPCs revoked; historical tables retained; effective change history remains. |
| 7 Clients | Admin Clients directory, add/edit, name/number search, explicit suggestions and duplicate prevention present. |
| 8 Private drafts / search only | Owner-only workspace RLS; private draft controls, existing-number handling and search-only mode present. |
| 9 Imported PO data | Ordered source item identifiers/repeats, catalog match, source fallback for missing Items, optional admin catalog addition, separate brand, pack/size and other mapped fields present. No PO quantities/weights added. |
| 10 Inspection | Select EST, confirm shown EST and different observed EST separate; authentic observations retained; review priority, mobile cards and draft print present. |
| 11 Approved PO | Four data columns: Item No., Description, Class, EST / Plant; separate admin evidence and admin edit/delete controls present. |
| 12 Delivery | Independent approved-PO association, delivery number, private original, SAP parsers, automatic match/preview present. |
| 13 Weights / quantities | Useful Weight selection when Catch Weight is zero; blanks not replaced with zero. Export lb unit omission corrected in this audit. |
| 14 Repetitions / ambiguity | Source lines retained; explicit approved-line association for ambiguous ESTs; unresolved rows visible and partial export confirmation present. |
| 15 Versions | Delivery approved snapshot/version comparison and stale export block present. |
| 16 Table customization | Account/table-specific local preferences, drag resizing, numeric Width(px), mobile reorder controls, sorting/facets and explicit Product Search present. |
| 17 Delivery export | Exactly five fixed data columns; PO[number] - D[number] [client].xlsx. Later total-row request supersedes plain body-only output. |
| 18 Navigation / help / skins | Three skins retained; help structure within Help; catalog import and sync in Settings. Remaining Spanish account/sync/history labels translated in this audit. |
| 19 Deployment | Current source fetched instead of assuming previous commit IDs. Pages must be hash-checked after publication. |
| 20 Catalog search | Complete safe catalog RPC; shared exact matcher, boundary whitespace normalization preserving significant identifier characters; query errors and races handled. Global exact search explicitly ignores other filters. |
| 21 Initial validation | 467 existing nonempty item/EST associations recorded separately; idempotent admin initialization. No new products. |
| 22 Meaning of validation | Separate profile label; not a physical observation or receipt. No physical dates/frequencies/priority changes. Receipt display distinguishes delivery upload from unknown actual receipt date. |

## Later requests retained

- Unknown import Items: Edit / Add to catalog, Edit all missing / Add all edited to catalog; mapped product fields and brand selection/creation.
- Delivery first: imports without an approved PO create a private PO In review; export blocked until admin approval.
- Missing EST batch entry: Fill missing ESTs / Save all; does not create physical verification.
- Approval queue: preflight saves and handles definitively rejected blank-EST approval jobs without treating unsent jobs as synchronized.
- Delivery export driven only by received delivery rows: zero quantities omitted, absent PO rows never injected, blank quantities retained.
- Three blank rows and boxed Total Quantity in column D, independent of screen column order.

## Corrections from this audit

1. Translate account, connection, pending-send, photo and history-domain interface strings to English; preserve the user-selected name Invitados.
2. Preserve lb explicitly in exported Catch Weight cells (kg and other supplied units remain preserved).
3. Revoke obsolete TRUNCATE, REFERENCES and TRIGGER grants on legacy inspection_snapshots from client roles. No rows changed; owner-scoped row privileges retained.

## Open items

- Create the shared Invitados Auth account with the user's chosen email and password through a secure account-creation flow, then apply its label. Never invent credentials or repurpose other accounts.
- Complete fresh mobile / three-skin / normal-user live visual regression before calling the entire mandatory checklist newly verified.
- Any new issue found in that regression must be fixed and recorded; unchanged overall layout is intentional, not proof of a stale release.
