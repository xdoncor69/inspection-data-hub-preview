# Centralized Purchase Order drafts

All signed-in accounts now see the same saved draft list in Purchase Orders. The UI uses “Drafts”, “Draft · pending inspection”, “Approved for Inspection” and “Approved · pending delivery”. Draft printouts remain “DRAFT — NOT APPROVED”.

The administrator can review, modify, delete and approve any shared draft. A normal user can view all drafts and edit/delete only drafts they created. Approval replaces the draft with the same approved PO reference for everyone. Catalog/customer master permissions and inspection-evidence privacy remain unchanged.

## Incremental storage change

The existing inspection_po_workspaces record owned by the configured inspection administrator is now the authoritative shared draft workspace. Its original drafts were retained and the other saved drafts copied into it by technical draft ID, without merging lines or changing ESTs. The migration aborted if IDs or PO numbers were ambiguous. The original per-account records remain as server-side compatibility archives; they are not merged again on every read. No catalog products, observations, approved POs, deliveries or files were reconstructed.

The migration retained 2 drafts and 13 lines in the shared workspace. It preserved raw line contents and actual creator attribution. No fictitious observation or reception was added.

Authenticated reads use inspection_read_draft_workspace(). Administrators receive complete drafts; normal accounts receive a whitelist without physical dates, physical authors, verification indicators, observed EST lists, change evidence, notes or observation history. Raw workspace reads are administrator-only under RLS. Draft CSV exports include evidence fields only for the administrator.

The existing inspection_queued_commit() endpoint, account-owned pending queue, operation receipts, catalog generation guard and write lock order are reused. The workspace branch now merges changed draft IDs against the central record with optimistic conflict checks. Normal accounts cannot modify another creator's draft, spoof attribution or inject physical verification fields. Duplicate PO numbers are rejected. A delayed pending send cannot recreate a draft superseded by an approved PO. An unsupported nonempty legacy Item-by-Item scratch-log send remains explicitly pending for review rather than being silently dropped or presented as saved.

inspection_draft_workspace_stamp() provides a safe change stamp used by the existing 15-second refresh loop, so an upload from another account becomes visible without switching accounts. Approval still uses the existing administrator RPC, now reading from the same shared workspace.

Pending-order notices now originate from new drafts in the shared workspace and refer to the order the administrator can open. External Web Push remains disabled pending the separate authorization already requested; this change does not enable it.

## Validation

Run tests/central-drafts.sql against the configured project: fixtures are transaction-scoped and rolled back. Tested normal-account creation, shared reads, real creator attribution, evidence forgery/leak prevention, denial of edits to another creator's draft, denial of normal-user approval, duplicate PO rejection, idempotent retry, stale edit conflict, owner deletion, administrator approval of another account's draft, and safe approved visibility after the draft is retired. No test records remain.

The notification trigger regression test also passes against the central workspace. Inline JavaScript parsing and draft-edit permission checks passed. The security advisor reported no new warnings/errors (the pre-existing Auth password-protection warning remains outside this change). Native signed-in browser/mobile interaction was not exercised in this task.

Database migration: centralize_drafts_with_admin_only_evidence. database/central-drafts.sql is reference for the already-applied migration and must not be run blindly.
