# Compact default table widths

Adjustable tables now measure each header with the current computed font, casing, letter/word spacing, sort indicator and cell padding. The minimum also reserves the existing drag grip and resize edge. Screen headers stay on one line; table body content may wrap and wide tables keep their existing horizontal scrolling.

Default widths use that minimum, except description columns start at 260 px and customer columns at 180 px (or their header minimum if larger). Customer-directory Name columns receive the same customer allowance. Old hardcoded colgroup widths and stretched table measurements no longer determine fresh defaults.

Account/table preference keys and column identities are unchanged. Saved column order and wider custom widths are retained; widths below the measured header minimum are raised to that minimum. Mouse, touch and keyboard resizing use the same minimum. Metrics refresh when the skin, viewport or loaded fonts change. Description auto-height handling remains unchanged. Catalog inline editors can shrink within their column.

No database, permission, import, export or data changes. Print header wrapping remains as before. No reset/numeric column controls were added.

Validation: 22 inline scripts compile. Code-only tests cover header/sort/control allowances, compact defaults, description/customer exceptions, minimum resizing, preference/order retention, account isolation and skin/viewport remeasurement. Delivery-export code and layout-storage key construction verified unchanged. No browser, screenshots or rendered preview used. Actual device rendering remains untested.

Run node tests/compact-table-widths.cjs preview/index.html (public: index.html).
