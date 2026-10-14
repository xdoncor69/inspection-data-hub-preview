# Inspection evidence presentation retired — 2026-10-14

All accounts, including the administrator, now see published/selected EST values without checked/un-checked status, per-line physical dates/authors, elapsed inspection time or observation counters.
Approved PO/delivery evidence HTML is no longer generated. Draft desktop/mobile rows no longer render verification indicators. Product profiles show EST and a brief administrator priority instead of observation history, dates, frequency cards or reason tooltips. Priority calculations remain unchanged internally.
The invoice overview and its CSV no longer contain physical history/frequency/time columns. Draft CSV no longer contains verification date, observed ESTs or physical notes. Read-only observation record views and the corresponding physical-change-history presentation were retired. Catalog change history remains.
Legacy reference trend text is retained in storage but not displayed. Product/brand identification notes, administrative validation and delivery upload references remain separate from physical history.
The Guide now describes the workflow and available values without inspection-history panels or thresholds. It makes no claim that every line was physically checked.

Administrator entry controls remain available for genuine observed ESTs; selecting/editing an EST and approving a PO still do not create observations automatically. Priorities, stored observations, dates/authors and historical records are preserved. No existing records or approved ESTs were changed.
Quick-entry selection records the current catalog EST shown to the administrator only after explicit administrator confirmation; no historical verification date or status is shown.

## Backend
Applied migration omit_inspection_reference_trends_from_normal_reads modifies existing safe official/catalog readers. Normal accounts no longer receive reference trend text or initial-review reasons. Physical observation domains and private line markers remain excluded by the existing safe snapshot/draft/delivery readers and raw snapshot-column grants.
Administrator raw reads are retained for internal priority calculation and authentic evidence preservation; the app no longer presents the evidence.
No data DML or permission expansion. The official-record checksum before/after was unchanged; role tests confirm normal API privacy and admin internal evidence retention.

## Validation
20 inline scripts compile. Tests cover both roles, empty evidence output, equal visible output for checked/un-checked mobile lines, absence of physical dates/authors/counts/time in product output and CSV, and priority labels without diagnostic tooltips.
Invoice overview has eight matched headers/columns after removing history columns. Observation view elements are structurally removed or their old renderers emit no history. Primary observation writer and priority algorithm are unchanged.
SQL role tests cover David/Ariadna official state, catalog references, shared drafts, approved snapshots and deliveries, plus continued denial of direct private-snapshot reads. Existing security-advisor notices remain unrelated; no new warnings.
No browser, screenshots, previews or EXE changes. Identification notes are retained as entered; the change removes generated inspection disclosures rather than deleting user notes.
