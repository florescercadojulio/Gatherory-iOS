# Gatherory iOS

Gatherory's primary planning app uses SwiftUI and SwiftData, with offline edits
and authenticated synchronization to the Gatherory server.

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
- `Gatherory/Localization/`, `Localizable.xcstrings`, and `InfoPlist.xcstrings`
  inside `Gatherory/`: UI copy and permission localization.
- [Authentication contract](docs/auth-integration.md),
  [offline sync](docs/offline-sync.md), and [release guide](docs/app-store-release.md).

Some older docs retain early product assumptions. Verify current source and
configuration before treating their status notes as current implementation.

## Verification

Open `Gatherory.xcodeproj` and use the `Gatherory` scheme. For unit tests, select
an installed iOS Simulator and the `GatheroryTests` target. After changing copy,
run `bash scripts/verify-localizations.sh`. Test native permissions, sharing,
and account switching on a physical device when relevant.

Runtime endpoints and feature flags are in `Config/Debug.xcconfig` and
`Config/Release.xcconfig`; Release currently targets `https://app.gatherory.com`.
