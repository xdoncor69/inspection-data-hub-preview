# Mobile form entry and product type selection

Mobile and coarse-pointer form controls use 16px text to avoid iOS automatic focus zoom. The viewport retains manual pinch zoom. Desktop mouse-only styling is unchanged.

Product Search row editing and Edit all results use a locked Meat/Poultry select for Product type. It unlocks only during administrator editing; connection and role refreshes retain that restriction. Blank/unsupported values require an explicit choice and are not silently changed to Meat.

Validation: all inline scripts parsed; existing catalog batch tests passed; tests/mobile-product-entry.cjs covers dropdown choices, placeholders, edit hooks, role/connection states and mobile CSS/viewport constraints. No browser, screenshot or physical iPhone test was performed. No database or catalog data changes.
