# Color themes

Account → Color Theme offers Gatherory Blue, Orchid, Sage, Rose, Coral, Amber,
Ocean, and Midnight. The existing `appColorTheme` preference and original case
raw values remain compatible. Theme names are localized in English and Spanish.

## Color ownership

- Native controls inherit `.tint` from `.appColorTheme(...)` at the app root.
- Custom controls, charts, selections, badges, and avatar fallbacks use
  `AppTheme.ColorToken`. These remain concrete SwiftUI `Color` values, so they
  also work in gradients, strokes, charts, and UIKit bridges.
- A color-affecting custom UIKit trait bridges `appColorThemeChoice` to dynamic
  colors. Each token resolves against the rendering view's traits, including
  theme, appearance, increased contrast, and elevated surfaces. Subtree previews
  and sheets therefore use the same palette without changing saved preferences.
- `AppTheme.Artwork.colors(for:)` resolves the same selection. Custom themes blend
  30% of its brand trio into the category gradients, preserving their individual
  palettes. Uploaded photos and artwork are never tinted.
- Success, warning, destructive, and main-event marker colors retain their
  meanings. User photos, album art, neutral materials, and provider branding
  retain their original colors. Do not recolor these as app accents.

Use `accent` for an interactive highlight and `onAccent` for a label directly on
an opaque accent fill. Custom themes use white in light mode and black in dark
mode; Gatherory Blue retains Apple's blue scheme with white filled-control labels.
Native `.borderedProminent` buttons also explicitly use `onAccent`, because their
default white label does not adapt to a brighter custom dark-mode tint.
Use `onMedia` for photo overlays. Surfaces and normal labels use adaptive system
colors. Avoid fixed brand hues or reading `AppTheme.active` to paint a view;
that convenience reads the saved preference rather than a subtree override.

## Palette

Gatherory Blue uses Apple's dynamic `UIColor.systemBlue`, `systemIndigo`, and
`systemTeal`, including their system appearance and accessibility adaptations.
It has no custom blue hex values.

Custom primary accent hex values below are sRGB. Each also has light and dark
Increase Contrast variants. Secondary and tertiary accents follow the same
appearance rules.

| Theme | Light | Dark |
| --- | --- | --- |
| Gatherory Blue | System Blue | System Blue |
| Orchid | `#7540A3` | `#C49AEB` |
| Sage | `#246B50` | `#7ACAA5` |
| Rose | `#A12C57` | `#F284AA` |
| Coral | `#A83827` | `#F28B78` |
| Amber | `#895600` | `#E8AE43` |
| Ocean | `#00617A` | `#62CBE5` |
| Midnight | `#3C478E` | `#9AA8F5` |

Calculated solid-color sRGB contrast across all three custom accent roles and
their variants: white on light accents is at least 6.13:1; black on dark accents
is at least 8.66:1. Dark accents against `#2C2C2E` are at least 5.74:1, and against
`#1C1C1E` at least 7.01:1. These calculations do not establish contrast for a
translucent fill over arbitrary photography; those controls retain native
materials and existing media readability treatments.

## Preview and evidence

Open `Gatherory/DesignSystem/Theme/AppColorThemePreview.swift` in Xcode Canvas:

- **Themes · Light** and **Themes · Dark** show every theme together.
- **Theme · Interactive Light** and **Theme · Interactive Dark** let you change
  the theme and appearance using local state. They include the production
  artwork renderer, avatar fallback, budget card, and native controls. No sign-in,
  backend, or saved-preference changes are needed.

October 21, 2026: simulator build passed (`/tmp/gatherory-color-theme-final-build.log`)
and localization coverage passed for 1,540 English/Spanish strings. Canvas
galleries rendered all eight accents with stable feedback colors in both
appearances. Live switching from Blue to Rose updated native controls, direct
tokens, artwork, and avatar fallbacks together. Switching to dark mode exposed
the native filled-button label contrast issue; the final preview confirms black
labels on the brighter dark accents after the correction. The budget card uses
the same dynamic accent token; its full chart was not separately inspected in
Canvas during this pass. No unit tests or physical-device installation were run.

October 22, 2026: restored Gatherory Blue's native Apple system blue/indigo/teal
palette and white filled-control foreground. The custom-theme contrast figures
above do not apply to the system palette. Other theme choices are unchanged.
