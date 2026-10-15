# Product Search catalog tools

Product Search provides administrator-only Import products and Export template (.xlsx) actions. Import products opens the existing Settings product importer directly in Excel/CSV Batch mode, reusing its mapping, comparison, duplicate checks, explicit update review and official writer. Product type is now recognized as a source header.

The template contains Item No., Description, Brand, Product type, Product family, Pack / Size and EST, plus a separate instructions sheet. The first 10,000 Item cells use Excel text format to help preserve leading zeros. Only Meat and Poultry are visible choices. Brand stays separate from Description. Delivery quantities and weights are excluded.

Global Search has Edit all results, Save all and Cancel. Editing unlocks each row independently while keeping Item numbers immutable. Search controls and competing row/bulk edits are paused, sorting retains existing row nodes, and background catalog refresh does not redraw unsaved cells. Save all validates all changed rows before sending one existing queued-commit operation. Missing or duplicate identifiers, unsupported fields, missing required data and changes to the original catalog row since editing began are rejected. Cancel sends nothing.

The new client helper uses existing administrator-only catalog writes, optimistic base records, account-bound idempotent queue and effective-change audit. It updates catalog/reference primary values without writing observations, receipts, approved POs, deliveries or initial validations. Pending sends are explicitly identified as not synchronized. Data is not presented as saved unless the confirmed catalog contains the requested values. No schema migration or permission expansion was made.

The routine connection banner is initially hidden and stays hidden for success messages. Error messages may still show it; the offline/login overlay, Settings connection information and Pending sends control remain available.

Validation (code only): 22 scripts compile; pure policy, Save all handler, cancellation, stale/invalid rejection, immutable IDs, role guards, one queued commit and pending/confirmed reporting tested. A real XLSX buffer roundtrip verified seven recognized headers, text format through row 10,001 and a leading-zero Item. SQL with Ariadna's authenticated role verified official catalog read and rejected a catalog write using an existing real item; transaction rolled back, no test products retained. No browser, screenshots or visual preview used.

Run node tests/product-catalog-tools.cjs preview/index.html (public repository: index.html).
