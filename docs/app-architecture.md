# Gatherory App Architecture

## Overview

The project currently uses the standard SwiftUI and SwiftData application template. This is a good point to adopt a feature-first architecture: user-facing code is grouped by feature, while infrastructure shared across features is kept in clearly defined supporting layers.

This structure is intended to support authentication, local persistence, networking, assets, localization, testing, and future features without over-engineering the initial application.

## Product Vision

**Gatherory** is a shared planning space where couples and the people they trust collect, discuss, organize, and decide on wedding ideas together.

The initial experience can be bride-forward because brides are likely to represent a large part of the audience, but it should never imply that wedding planning belongs to one gender. The language, imagery, onboarding, and permissions should welcome brides, grooms, partners, family members, wedding-party members, and professional planners. Use the relationship-based roles `Host`, `Collaborator`, and `Guest` instead of gender-coded assumptions.

The core product promise is:

> Turn scattered wedding inspiration into shared decisions.

The primary experience should make it easy to:

- Create a private wedding space.
- Invite a partner and other collaborators.
- Save ideas with images, links, notes, categories, and estimated costs.
- Organize ideas into boards such as venues, attire, flowers, food, music, and photography.
- React, comment, compare, and vote without losing the original idea.
- Mark an idea as shortlisted, decided, booked, or rejected.
- See recent activity and understand who changed what.
- Control who can view, contribute, vote, or manage the wedding space.

The visual personality should feel celebratory, warm, polished, and calm. It should avoid becoming so traditionally feminine that partners or other collaborators feel like guests in someone else's application. Photography and user-created inspiration can provide much of the emotion, allowing navigation and controls to remain clear and platform-native.

### Product Principles

1. **Collaboration before collection.** Saving an idea is only the beginning; conversation and decisions are the valuable outcome.
2. **A shared space, not a public feed.** Wedding content and discussions are private by default, with explicit invitations and understandable permissions.
3. **Fast capture.** Adding a photo, link, note, or rough cost should take only a few actions.
4. **Calm decision-making.** Status, voting, comparison, and filtering should reduce planning overload instead of adding it.
5. **Inclusive by design.** Copy and imagery should not assume gender, family structure, culture, budget, ability, or wedding format.
6. **Native and accessible.** Prefer familiar Apple interaction patterns and honor system appearance and accessibility settings.

## Recommended Folder Structure

```text
Gatherory/
├── App/
│   ├── GatheroryApp.swift
│   ├── AppEnvironment.swift
│   ├── AppRouter.swift
│   └── RootView.swift
│
├── Features/
│   ├── Authentication/
│   │   ├── Models/
│   │   │   ├── User.swift
│   │   │   └── AuthenticationState.swift
│   │   ├── Services/
│   │   │   ├── AuthenticationService.swift
│   │   │   └── LiveAuthenticationService.swift
│   │   ├── Views/
│   │   │   ├── LoginView.swift
│   │   │   ├── SignUpView.swift
│   │   │   └── ForgotPasswordView.swift
│   │   └── AuthenticationModel.swift
│   │
│   ├── Onboarding/
│   │   ├── Views/
│   │   └── OnboardingModel.swift
│   │
│   ├── Home/
│   │   ├── Models/
│   │   ├── Views/
│   │   └── HomeModel.swift
│   │
│   ├── PlanningWorkspace/
│   ├── Ideas/
│   ├── Boards/
│   ├── Collaboration/
│   ├── Decisions/
│   ├── Timeline/
│   ├── Profile/
│   └── Settings/
│
├── Data/
│   ├── Networking/
│   │   ├── APIClient.swift
│   │   ├── APIEndpoint.swift
│   │   ├── APIError.swift
│   │   └── DTOs/
│   │
│   ├── Persistence/
│   │   ├── Models/
│   │   ├── PersistenceController.swift
│   │   ├── Schema/
│   │   │   ├── AppSchemaV1.swift
│   │   │   └── AppMigrationPlan.swift
│   │   └── Repositories/
│   │
│   └── Security/
│       ├── KeychainStore.swift
│       └── SessionStore.swift
│
├── DesignSystem/
│   ├── Components/
│   ├── Styles/
│   ├── Typography/
│   │   └── AppTypography.swift
│   └── Theme/
│       ├── AppTheme.swift
│       ├── ThemeColors.swift
│       ├── ThemeSpacing.swift
│       └── ThemeShape.swift
│
├── Music/
│   ├── MusicCatalog.swift
│   ├── MusicSearchView.swift
│   └── Providers/
│       ├── AppleMusicCatalogProvider.swift
│       └── SpotifyCatalogProvider.swift       // Future
│
├── Shared/
│   ├── Extensions/
│   ├── Utilities/
│   ├── Models/
│   └── Views/
│
├── Resources/
│   ├── Assets.xcassets/
│   ├── Localizable.xcstrings
│   ├── Preview Content/
│   └── Configuration/
│
└── SupportingFiles/
    ├── Info.plist
    ├── Development.xcconfig
    ├── Production.xcconfig
    └── Gatherory.entitlements

GatheroryTests/
├── Features/
├── Data/
├── TestDoubles/
└── Fixtures/

GatheroryUITests/
├── Authentication/
└── CriticalFlows/
```

Create these directories as they become necessary rather than adding every empty directory at the beginning of development.

## Responsibilities

### App

The `App` directory contains the composition root and the application's highest-level navigation.

- `GatheroryApp` creates long-lived dependencies and injects them into SwiftUI.
- `AppEnvironment` owns configured service implementations and the SwiftData container.
- `AppRouter` represents application-level navigation when that navigation becomes sufficiently complex to warrant a dedicated type.
- `RootView` decides whether to show session restoration, authentication, onboarding, or the signed-in application.

The app entry point should not gradually accumulate feature logic.

### Features

`Features` is the primary organizational boundary. Each feature keeps its views, observable state, feature-specific models, and service interfaces close together.

Developers ordinarily work on a feature such as authentication or profile, not on every view or model in the application. A feature-first structure therefore remains easier to navigate than global `Views`, `Models`, and `ViewModels` folders as the codebase grows.

### Data

`Data` owns communication with systems outside the feature layer:

- HTTP requests and responses
- SwiftData persistence
- Keychain access
- Repository implementations
- Mapping between network, persistent, and application models

Feature views should not construct raw HTTP requests, issue Keychain queries, or contain persistence rules.

### DesignSystem

The design system contains reusable visual primitives, typography, colors, component styles, and theme definitions. A component should move here only when it is genuinely shared; feature-specific UI should remain inside its feature.

The theme is a semantic vocabulary, not a parallel rendering framework. It should build on SwiftUI, system controls, system text styles, SF Symbols, and adaptive asset colors instead of wrapping every native API.

### Shared

`Shared` contains small reusable types with no natural feature owner. Treat this as a narrow exception rather than a default destination. If a shared folder becomes large, its contents probably need a clearer domain or feature boundary.

### People and Timeline Domain

Keep a person's wedding role separate from both attendance and planning permission:

- A `Host` is part of the couple and normally has management access.
- A `Collaborator` helps with ideas, decisions, and timeline events.
- A `Guest` belongs to the eventual invitation list and isn't assignable to planning work by default.

Timeline events should store structured fields instead of combining them into display strings: `title` is the event name, `category` is the event type, `scheduledAt` is the date and time, `eventLocation` is a structured place, stable participant IDs identify the planning team, and optional image data identifies the event visually. `EventLocation` keeps the Apple Maps identifier, normalized full and short addresses, coordinates, an optional unit or floor, and an optional user-facing location name. Persist this value rather than `MKMapItem` so the domain and backend stay independent of MapKit while retaining enough information to display the place, open it in Maps, or refresh provider details later. Persist participant IDs rather than names so profile edits don't break assignments and the backend can enforce access independently of the UI. In the interface, prefer these direct domain labels over conversational prompts like “what,” “why,” or “who.” Event completion is reversible from the collection context menu and event detail; destructive management such as deletion belongs in the event detail view.

The location editor uses `MKLocalSearchCompleter` for live address and point-of-interest suggestions, then resolves the selected completion with `MKLocalSearch`. Searching Apple Maps doesn't require reading the device's current location, so this flow must not request location permission. If a future “Use My Location” action is added, treat it as a separate, explicit capability and request permission only in response to that action.

Event details use the stored coordinates to request the matching daily forecast from WeatherKit. Keep this request detail-scoped instead of fetching forecasts for every row in the timeline: opening an event is a clear signal of interest, controls request volume, and keeps weather secondary to the event itself. Show the condition, high and low temperatures, and precipitation chance only when WeatherKit returns the event's calendar day. If the date is beyond the returned forecast window, say that the forecast will be available closer to the event instead of presenting historical averages as a prediction.

`EventWeatherProviding` is the provider boundary. Its WeatherKit implementation maps framework values into app-owned `EventWeatherForecast` and `EventWeatherAttribution` values, which keeps views testable and leaves room for a server-backed implementation for scheduled checks and notifications. Weather data may be cached only temporarily to improve WeatherKit performance; don't persist it as shared event data. Whenever forecast data appears, display the Apple Weather mark linked to WeatherKit's legal attribution page. The app target also needs the WeatherKit entitlement, and the explicit App ID must have WeatherKit enabled in the Apple Developer portal before live requests can succeed.

References:

- [WeatherKit](https://developer.apple.com/documentation/weatherkit)
- [Weather attribution](https://developer.apple.com/documentation/weatherkit/weatherattribution)
- [Enable WeatherKit for an App ID](https://developer.apple.com/help/account/services/weatherkit)

### Image Sources

Ideas, registry gifts, and timeline events share one image-source flow. It offers the system Photos picker, an on-device camera capture, and Image Playground when `ImagePlaygroundViewController.isAvailable` is true. The Image Playground integration must use Apple's presented `imagePlaygroundSheet` experience; it isn't a headless generation service. Seed the sheet with domain-specific concepts and, when replacing an image, provide the existing artwork as the optional source image.

Image Playground returns a temporary file URL. Read the file immediately into app-owned image data before dismissing the sheet, then let the feature's normal save operation persist or upload it. Keep camera permission copy narrowly scoped to ideas, gifts, and events. Unsupported sources remain visible but unavailable with an accessibility explanation so the layout stays predictable across the simulator and devices without Image Playground.

### Resources

`Resources` contains compiled application resources such as images, colors, strings, preview data, and non-secret configuration files. Swift source remains outside this directory.

## Dependency Direction

```text
SwiftUI View
     ↓
Feature Model
     ↓
Repository Protocol
     ↓
Live Repository
  ↙      ↓       ↘
API   SwiftData  Keychain
```

Dependencies should point toward application behavior rather than from low-level infrastructure back into UI features. Protocols at important boundaries allow tests and previews to substitute deterministic implementations.

For the initial app, these layers can remain in one Xcode target. Separate Swift packages are useful later when a boundary is independently reusable, separately owned, or materially improves build performance; they are not required merely to reproduce the folder structure.

## Music Catalog Providers

Song ideas use an app-owned `MusicTrack` value rather than storing `MusicKit.Song` or a future Spotify SDK model. The shared value includes the provider ID, provider catalog ID, title, artist, album, artwork URL, external URL, duration, and ISRC when available. This makes it suitable for persistence and backend synchronization without coupling wedding ideas to one vendor SDK.

```text
Ideas UI
   ↓
MusicCatalog
   ↓
MusicCatalogProviding
  ↙                 ↘
Apple Music          Spotify / future providers
MusicKit             provider SDK or REST API
```

Each provider maps its native response into `MusicTrack`. A saved `PlanningIdea` can optionally carry that track reference, so it continues through the existing collaboration, decision, and detail flows. Provider-specific authorization and search stay behind `MusicCatalogProviding`; views request a provider by `MusicProviderID` and never import a provider SDK directly.

Apple Music is the initial live provider. Spotify is represented only as a provider ID until its authorization and catalog implementation are added. Treat ISRC as useful cross-catalog matching metadata, not as a guaranteed unique primary key; the stable identity remains the provider ID plus the provider's catalog ID.

Request music authorization in context, when someone chooses to find a song. The app must include `NSAppleMusicUsageDescription`, and its explicit App ID must have the MusicKit App Service enabled in the Apple Developer portal.

References:

- [MusicKit](https://developer.apple.com/documentation/musickit)
- [Enable MusicKit for an App ID](https://developer.apple.com/help/account/services/musickit)

## Authentication and Session Management

Recommended separation:

```text
AuthenticationModel
├── controls loading, error, and authentication state
└── calls AuthenticationService

AuthenticationService
├── login
├── registration
├── refreshSession
├── logout
└── restoreSession

SessionStore
├── retains the current in-memory session
└── stores sensitive tokens through KeychainStore
```

Store access tokens, refresh tokens, passwords, and other small secrets in Keychain, not in `UserDefaults`, SwiftData, property lists, or source files. Apple describes Keychain as encrypted storage for credentials and other small secrets. Prefer not to retain a user's password after authentication; retain server-issued credentials instead.

If the app supports Sign in with Apple, keep the platform-specific authorization interaction inside the authentication feature and send the returned credential to the backend for verification.

References:

- [Using the Keychain to manage user secrets](https://developer.apple.com/documentation/security/using-the-keychain-to-manage-user-secrets)
- [Implementing user authentication with Sign in with Apple](https://developer.apple.com/documentation/authenticationservices/implementing-user-authentication-with-sign-in-with-apple)

## Persistence

The project already uses SwiftData. Keep persistent models separate from network response objects:

```text
Data/Persistence/Models/EngagementRecord.swift  // @Model
Data/Networking/DTOs/EngagementDTO.swift        // Codable response
Features/Home/Models/Engagement.swift           // Optional application model
```

This prevents a server response change from silently becoming a database migration.

Create the `ModelContainer` in `AppEnvironment` or a persistence factory and inject it at the application boundary. Define the schema explicitly and add versioned schemas before shipping stored user data. SwiftData supports automatic migrations and explicit `SchemaMigrationPlan` implementations when automatic migration is insufficient.

Use an in-memory `ModelConfiguration` for previews and persistence tests.

Reference: [ModelContainer](https://developer.apple.com/documentation/swiftdata/modelcontainer)

## Networking

A small networking abstraction is sufficient:

```swift
protocol APIClient: Sendable {
    func send<Response: Decodable>(
        _ endpoint: APIEndpoint<Response>
    ) async throws -> Response
}
```

Feature repositories construct endpoints and map DTOs into application models. The shared API client handles mechanics such as:

- Base URL and request construction
- JSON encoding and decoding
- Authentication headers
- HTTP response validation
- Error normalization
- Coordinated token refresh

Use `URLSession` async APIs for network operations. Keep backend secrets off the device: configuration embedded in an application bundle can ultimately be inspected, so privileged credentials must live on a server.

Reference: [URLSession](https://developer.apple.com/documentation/foundation/urlsession)

## Assets and Localization

Keep colors, app icons, symbols, and images in asset catalogs. Asset catalogs select the correct resource variation for appearance, resolution, device, and localization at runtime.

Suggested catalog organization:

```text
Assets.xcassets
├── AppIcon
├── Colors/
│   ├── Background
│   ├── Surface
│   ├── TextPrimary
│   └── BrandPrimary
├── Illustrations/
├── Icons/
└── Photography/
```

Use semantic names such as `TextPrimary` and `BrandPrimary`, rather than appearance-specific names such as `DarkGray` or `PinkButton`.

Add `Localizable.xcstrings` early. Xcode string catalogs can extract SwiftUI strings, manage translations and plurals, and provide language or device variants.

References:

- [Managing assets with asset catalogs](https://developer.apple.com/documentation/Xcode/managing-assets-with-asset-catalogs)
- [Localizing and varying text with a string catalog](https://developer.apple.com/documentation/Xcode/localizing-and-varying-text-with-a-string-catalog)

## Human Interface and Theme Strategy

The application should follow Apple's Human Interface Guidelines wherever possible. The theme provides consistent brand expression without disconnecting the app from system behavior.

### Appearance

Follow the person's system Light or Dark Mode setting. Apple recommends avoiding a separate app-specific appearance control in most cases because people expect applications to honor the system setting.

- Do not force `.preferredColorScheme` in production UI.
- Start with system background and label colors.
- Define custom brand colors as named asset-catalog color sets with `Any`, `Dark`, and increased-contrast variants.
- Use semantic names based on purpose rather than pigment.
- Verify illustrations, photography overlays, gradients, shadows, and materials in both appearances.
- Prefer SF Symbols for interface icons because they scale and adapt with system appearance.

Suggested semantic color tokens:

```text
BackgroundPrimary       Main screen background
BackgroundSecondary     Grouped sections and secondary surfaces
Surface                 Cards and contained controls
SurfaceElevated         Sheets or content above another surface
TextPrimary             Primary labels
TextSecondary           Supporting copy and metadata
BrandAccent             Primary actions and selected controls
CelebrationAccent       Sparse decorative or success emphasis
Border                  Dividers and card outlines
Success                 Confirmed or booked state
Warning                 Time-sensitive or incomplete state
Destructive             Delete and irreversible actions
```

The wedding aesthetic can use a warm neutral foundation with one restrained romantic accent. Avoid making pale pink the universal background or using low-contrast script text for essential information. User photography and mood boards should remain the most colorful elements on content-heavy screens.

Reference: [Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode)

### Typography and Dynamic Type

Use SwiftUI's semantic text styles instead of fixed font sizes:

```swift
Text(wedding.title)
    .font(.title.bold())

Text(idea.notes)
    .font(.body)

Text(idea.updatedAt, style: .relative)
    .font(.caption)
    .foregroundStyle(.secondary)
```

Use the system font for most UI. A tasteful custom typeface may be used sparingly for large celebratory headings or branding, but it must scale relative to a Dynamic Type text style:

```swift
Text("Gatherory")
    .font(.custom("BrandDisplay", size: 34, relativeTo: .largeTitle))
```

Additional requirements:

- Support every Dynamic Type size, including accessibility sizes.
- Allow labels to wrap instead of truncating meaningful text.
- Avoid fixed-height containers around text.
- Let horizontal layouts become vertical when large text no longer fits.
- Use `@ScaledMetric` when decorative spacing or icon sizes need to grow with text.
- Test the smallest size, the default size, and the largest accessibility sizes.

References:

- [Apple accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Applying custom fonts to text](https://developer.apple.com/documentation/swiftui/applying-custom-fonts-to-text)
- [Adaptive layout guidance](https://developer.apple.com/design/human-interface-guidelines/layout)

### Accessible Color and Status

Color must reinforce meaning rather than carry it alone. For example, a shortlisted idea can combine an accent color with a star symbol and the text `Shortlisted`; a booked vendor can combine green with a checkmark and the text `Booked`.

- Target at least 4.5:1 contrast for ordinary text and 3:1 for sufficiently large or bold text.
- Validate contrast in Light Mode, Dark Mode, and Increase Contrast.
- Observe `accessibilityDifferentiateWithoutColor` for custom visualizations and status treatments.
- Never distinguish votes, idea states, permissions, or budget status solely by hue.

References:

- [Color](https://developer.apple.com/design/human-interface-guidelines/color)
- [`accessibilityDifferentiateWithoutColor`](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilitydifferentiatewithoutcolor)

### Interaction and Assistive Technology

- Prefer standard SwiftUI controls, navigation, sheets, menus, and gestures.
- Keep interactive hit regions at least 44 by 44 points even when their visible glyphs are smaller.
- Give unlabeled icons explicit accessibility labels.
- Combine card contents into a useful VoiceOver element where reading every decorative element separately would be noisy.
- Announce state and value for voting, selection, progress, and permission controls.
- Do not make swipe gestures the only way to edit, approve, reject, or delete an idea.
- Respect Reduce Motion and avoid celebratory animation that flashes, loops indefinitely, or blocks interaction.
- Preserve the system's expected navigation and dismissal gestures.

References:

- [VoiceOver](https://developer.apple.com/design/human-interface-guidelines/voiceover)
- [Motion](https://developer.apple.com/design/human-interface-guidelines/motion)
- [Apple UI design tips](https://developer.apple.com/design/tips/)

### Theme Implementation

Start with static semantic tokens backed by system values and asset colors. Introduce environment-injected theme variants only if the product later needs distinct branded experiences, such as white-label planner spaces.

```swift
enum AppTheme {
    enum ColorToken {
        static let background = Color(.systemBackground)
        static let secondaryBackground = Color(.secondarySystemBackground)
        static let surface = Color(.secondarySystemGroupedBackground)
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let accent = Color("BrandAccent")
    }

    enum Spacing {
        static let compact: CGFloat = 8
        static let standard: CGFloat = 16
        static let spacious: CGFloat = 24
    }

    enum Radius {
        static let control: CGFloat = 12
        static let card: CGFloat = 18
    }
}
```

This type should contain reusable design decisions, not every literal used by the application. One-off layout values belong next to the feature that uses them.

## Application Composition

`GatheroryApp` should construct dependencies, while `RootView` handles top-level application state:

```swift
@main
struct GatheroryApp: App {
    private let environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment.authentication)
                .environment(environment)
        }
        .modelContainer(environment.modelContainer)
    }
}
```

Conceptually, `RootView` switches among these states:

```text
restoringSession → LaunchView
signedOut        → LoginView
needsOnboarding  → OnboardingView
signedIn         → MainTabView
```

The project's current deployment target supports the Observation framework, so `@Observable` and SwiftUI environment injection are appropriate for shared feature state. Apple recommends separating model data from views to improve modularity, testability, and reasoning about application behavior.

Reference: [Managing model data in your app](https://developer.apple.com/documentation/SwiftUI/Managing-model-data-in-your-app)

## Testing

Mirror production features in the unit-test target. Inject protocols for external dependencies so tests can replace them with stubs, fakes, or in-memory implementations.

Authentication tests should cover at least:

- Successful login
- Invalid credentials
- Network failure
- Session restoration
- Token refresh
- Logout and credential removal

Use Swift Testing for unit and integration tests and XCTest/XCUIAutomation for UI flows. Apple recommends a larger number of isolated unit tests, fewer integration tests, and a small number of critical end-to-end UI tests.

References:

- [Testing in Xcode](https://developer.apple.com/documentation/xcode/testing)
- [Adding tests to your Xcode project](https://developer.apple.com/documentation/xcode/adding-tests-to-your-xcode-project)

## Initial Adoption

Start with only the directories needed for the next features:

```text
App/
Features/Authentication/
Features/Home/
Data/Networking/
Data/Persistence/
Data/Security/
DesignSystem/
Shared/
Resources/
```

Add deeper subdivisions once multiple files justify them. The important architectural decision is maintaining clear ownership and dependency boundaries, not maximizing the number of directories.
