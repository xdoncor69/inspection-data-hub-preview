# Order overview dialogs

Opening either a draft or an approved order now presents a native modal instead of expanding details inside the order directory. Category tables remain visible behind the modal. Close and Escape release the selected order; switching order types clears the previous selection. Routing to another work view dismisses the overview.

The overview displays actual PO row counts and each linked delivery's actual source row count separately. Repeated items remain separate rows. PO and delivery item tables use closed details elements; their open/closed state survives refresh of the same order and resets for another order. Delivery-first drafts use existing authorized intake reads for their counts, source lines and protected original download. If only safe directory metadata is accessible, no line count or source data is invented and the details are identified as unavailable for that account.

The approved PO keeps its four data columns. Delivery exports, quantity-zero exclusion, blank quantities, stale-match protection, source-file access and genuine observation writes are unchanged. There are no database or permission changes.

The modal constrains its width/height to the viewport, allows table scrolling inside the table container, and wraps action groups and long file/customer text. Mobile inspection cards remain inside the collapsible PO section. Legacy edit dialogs launched from the overview are raised into a native action layer so their controls remain usable above the overview.

Validation: 21 inline scripts compile. Code-only tests cover modal opening, switching, Close/Escape, detail-state preservation and reset, count comparison, repeated source rows, escaping and action hooks. Existing directory tests pass for search, stage partitioning, 60 compact rows and safe metadata. Export/import/storage writers and physical-observation writer checked unchanged. No browser session, screenshots or rendered preview used; physical touch/device rendering has not been tested.

Run node tests/order-overview-dialog.cjs preview/index.html (public: index.html).
