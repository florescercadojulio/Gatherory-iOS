# Gatherory iOS

Gatherory's primary planning app uses SwiftUI and SwiftData, with offline edits
and authenticated synchronization to the Gatherory server.

The app supports iPhone and iPad running iOS/iPadOS 26 or later. The deployment
minimum is shared by Debug, Release, and the test targets. Newer SDK APIs must
remain behind availability checks with an iOS 26 fallback.

Start with the [cross-project AI onboarding guide](../../gatherory-web-app/docs/development/ai-onboarding.md)
for the product, shared decisions, repository ownership, and current release
context. Server/web lives in `../../gatherory-web-app`; the public landing site
lives in `../../gatherory-landing`.

## Source and documentation

- `Gatherory/Features/`: feature UI and behavior.
- `Gatherory/App/`: runtime configuration, account/session lifecycle, and app state.
- `Gatherory/OfflineSync/` and `Gatherory/Data/Persistence/`: local records,
  outbox delivery, synchronization, and media transfers.
- `Gatherory/DesignSystem/`: shared presentation components.
- [Color themes](docs/color-themes.md): palette choices, semantic color rules,
  appearance adaptation, and interactive previews.
- `Gatherory/Localization/`, `Localizable.xcstrings`, and `InfoPlist.xcstrings`
  inside `Gatherory/`: UI copy and permission localization.
- [Authentication contract](docs/auth-integration.md),
  [offline sync](docs/offline-sync.md), and [release guide](docs/app-store-release.md).
- [Event shared album](docs/shared-album.md): collage design, viewing, selection,
  saving to Photos, accessibility, and focused tests.
- [Event invitation cards](docs/event-invitation-cards.md): compact schedule,
  playlist artwork, and the latest authorized event update.
- [Blueprint setup feedback](docs/blueprint-setup-polish.md): preview saves, date
  confirmation, creation progress and retry behavior.
- [Explore rendering handoff](docs/explore-performance.md): lazy grids, fold
  behavior, identity and the row-alignment tradeoff.

Some older docs retain early product assumptions. Verify current source and
configuration before treating their status notes as current implementation.

## Verification

Open `Gatherory.xcodeproj` and use the `Gatherory` scheme. For unit tests, select
an installed iOS Simulator and the `GatheroryTests` target. After changing copy,
run `bash scripts/verify-localizations.sh`. Test native permissions, sharing,
and account switching on a physical device when relevant.

Run `bash scripts/verify-deployment-targets.sh` to check the effective minimum
OS settings for every app/test target and both device/simulator configurations.
This is a configuration check, not an iOS 26 runtime test. See the
[verification record](docs/testing-verification.md) for tested OS versions.

For adaptive layouts, native vertical controls and fold handling with Xcode 27.1,
see the [iPhone Duo implementation and verification guide](docs/iphone-duo.md).

Runtime endpoints and feature flags are in `Config/Debug.xcconfig` and
`Config/Release.xcconfig`; Release currently targets `https://app.gatherory.com`.
