# Idea category glass buttons

Each `Documents/*.icon` package is the editable Icon Composer source for one
idea category. `ictool` rendered the corresponding raster export in
`Gatherory/Assets.xcassets/IdeaCategoryGlass*.imageset` at 1x, 2x, and 3x.

The source artwork comes from `scripts/export-category-icon-sources.swift`.
These are intentionally pre-rendered controls: their liquid-glass appearance
does not depend on the OS version or on a runtime material behind the picker.
