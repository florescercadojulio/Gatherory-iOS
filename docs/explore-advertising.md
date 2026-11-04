# Explore advertising and paged discovery

## Exact native asset bounds — November 4, 2026

The validator report was reproduced with a host just **0.25 points shorter**
than its measured asset stack: the registered CTA extended outside
`NativeAdView`. The renderer previously accepted up to 0.5 points of overflow
and assigned full asset frames even when an undersized/zero-height host could
not contain them.

The renderer now requires exact containment. It detaches a displayed creative
before moving its registered assets; if the host is too small, it clears the
asset frames and requests the measured height before retrying registration.
A one-point internal inset prevents coordinate conversion from rounding a
fractional/RTL edge outward. Actual UIKit asset coordinates are checked after
SDK layout. Valid fitted
layouts restore the complete assets and register the same creative. Repeated
SwiftUI updates for that immutable creative leave the media and registered
asset content alone. No SDK update, validator disable switch, production ad-ID
change, consent bypass or application-owned ad click handler was introduced.

Regression coverage checks fractional/zero/shrunken host heights, recovery,
multiline/optional assets, narrow columns and RTL bounds. The sample-ad UI
harness scrolls real Google test inventory and, in Debug only, reads
registration/asset-containment diagnostics. This diagnostic is limited to
`-BlueprintAdsScrollVerification` and is absent from Release. See
[verification results](testing-verification.md) for executed runs and limits.

Google requires each asset view to be a descendant of the native ad view and
uses its registered assets for SDK-owned interaction and measurement. The
validator remains enabled. References: [display native ads](https://developers.google.com/admob/ios/native/advanced)
and [native validator](https://developers.google.com/admob/ios/native/validator).

## All Explore channels — November 2, 2026

All, Blueprints and Ideas now support native ads in browsing and typed search.
Search keeps organic relevance order; ads are separate placements after organic
items 6, 18, 30 and so on, counting either card type in All. Short or empty
results do not gain artificial rows. Local recent history and private event
planning remain ad-free. The Ideas filter shares the existing lazy, measured
native-ad renderer rather than creating a second ad implementation.

Consent, privacy choices, non-personalized requests and bounded inventory remain
in effect. Search text, idea content and account/event information are not sent
as advertising targeting. Covering Explore with either detail or Account pauses
requests and retains valid inventory; leaving Explore or changing accounts
invalidates it. This is a source change; no deployment or TestFlight upload was
performed. See the final test evidence in [verification](testing-verification.md).

## Beta enablement — October 23, 2026

At the release owner's request, Release now sets `EXPLORE_ADS_ENABLED=YES`
and retains `EXPLORE_ADS_TEST_MODE=NO` with Gatherory's production app/native
unit IDs. Debug still uses Google's sample native unit. Existing consent,
privacy choices, targeting restrictions and organic-feed fallback are unchanged.

This supersedes the disabled-Release rollout decision below; it does not mark
the provider or physical-device checks complete. The last AdMob inspection
(October 22) showed the app Requires review, separately from account approval.
Actual serving remains controlled by AdMob readiness, consent and inventory.
Use [Google's test-ad setup](https://developers.google.com/admob/ios/test-ads)
for interaction testing on physical devices; the Release flag does not make
live creatives test ads. No ad-account state, listing, SDK version or deployment
was changed here. See [beta release notes](app-store-release.md) and
[verification results](testing-verification.md).

## Setup snapshot — October 22, 2026

October 22, 2026. AdMob **account approval is complete**, confirmed in the
owner's Safari session. Pre-release setup now includes published regional
privacy messages, a verified live publisher file, and a deployed advertising
privacy disclosure. The app still **Requires review**: no public App Store
listing is linked, and AdMob's Gatherory search returned no result. Release
advertising remains disabled. Account approval does not establish app readiness.

## Verified AdMob setup

- App: **Gatherory iOS**, app ID `ca-app-pub-4218523458506277~8970323130`.
- Native advanced unit: **Explore Native Feed**, unit ID
  `ca-app-pub-4218523458506277/9237741437`. One existing unit was verified;
  no duplicate unit was created. Image and Video enabled; Google-optimized,
  All prices floor. No active mediation groups or enabled campaigns.
- [AdMob app dashboard](https://admob.google.com/v2/apps/8970323130/overview).
- Home explicitly says **Your account is approved** and ad serving is enabled at
  account level. Payment profile is complete. No payment or identity details
  were changed in this follow-through.
- App settings show no store details, **App verification: Not required** at this
  unlinked stage, and **Approval status: Requires review**. Verification wording
  here does not waive publisher verification after a store is linked.
- The Add store flow was searched for Gatherory; it returned “Can't find your
  app?” No unrelated listing or guessed store ID was saved.
- App-level maximum ad content rating is **T (Teen)**; G, PG and T are eligible,
  MA is blocked. This overrides the account's previous MA maximum. It is an ad
  content cap, not an App Store age-rating answer or a child-directed declaration.
  Stricter content/partner controls can reduce available demand; no revenue
  effect has been measured.

## Published privacy messages and publisher file

- **Gatherory European Consent** is **Published**, attached to Gatherory, with
  English default and Spanish additional language. Targeting: EEA, UK and
  Switzerland. Consent, Manage options and Do not consent are enabled; closing
  without a choice remains disabled. Privacy URL: `https://gatherory.com/privacy`.
- European ad partners are explicitly limited to the mandatory **Google
  Advertising Products** partner, rather than automatically including 198 common
  partners. Automatic addition of ad sources remains off. No custom publisher
  purposes, consent-mode integration, cross-app consent syncing or device-scanning
  special feature was enabled. Existing legitimate-interest controls/default
  and message-coverage fallback settings were retained.
- **Gatherory US Privacy Choices** is **Published**, attached to Gatherory, with
  English (en-US) default and Spanish (es). It includes the opt-out choice and
  targets **all current and future supported US states**. The US partner list
  is custom **Google only**, replacing 338 active partners. This is a deliberate
  narrow initial demand configuration; additional partners need review before use.
- US settings expose restricted data processing through ad-request/UMP signals;
  no separate account-wide RDP switch was present in this UI. Non-personalized
  requests and UMP choice handling remain in the app. No IDFA explainer or ATT
  prompt was added.
- Both messages were confirmed **Published** with their publish switches on;
  the confirmation described UMP integration/propagation, not a new agreement.
  Allow propagation before device validation. Publishing a CMP message is not
  proof of legal sufficiency or that the runtime consent path has passed.
- The live [app-ads.txt](https://gatherory.com/app-ads.txt) was verified in Safari:
  `google.com, pub-4218523458506277, DIRECT, f08c47fec0942fa0`.
  The old 404/deployment note was stale. Source is
  [landing public/app-ads.txt](../../../gatherory-landing/public/app-ads.txt).
  A live file alone does not establish that Google has crawled/verified it.
- The [privacy policy](https://gatherory.com/privacy#cookies) now explains the
  Explore Google Mobile Ads/UMP integration, possible SDK data collection,
  non-personalized requests, private-content exclusions, and privacy choices.
  Last updated October 22. The existing release-review label remains; unresolved
  general release disclosures were not declared complete. Spanish navigation
  identifies the shared policy as English; there is no separate Spanish policy.
- This factual disclosure was committed/pushed only in the landing repository:
  `c4090c9c85121b6dea07807ee70ec681593978fa`. Vercel production deployment
  `dpl_DutMWEcuvmbYn9mu2Bn3CZzW6iVP` is **READY**, assigned to `gatherory.com`,
  and the live disclosure/date were verified in Safari. No native release or
  backend deployment occurred.

Google's standard EU preview can still describe personalized-ad purposes and
precise geolocation even though Gatherory requests non-personalized ads and sends
no event/location targeting. The preview is not evidence that this app accesses
GPS for advertising. Verify the rendered UMP form, actual SDK behavior and consent
signals on a test device; do not claim this mismatch is resolved by configuration.

## Experience

All, Blueprints and Ideas use cursor-paged catalogs, with each stream requesting
20 organic items per page. Browsing and typed search share the same ad policy.
The first scheduled slot follows organic item 6; later slots follow items 18,
30, and so on. All counts Blueprints and Ideas together; organic relevance and
source order are preserved. Slots retain their positions as pages append. The
next three slots prefetch so a creative can be ready before its lazy anchor
appears. Recently viewed history and private event planning do not contain ads.
The grid retains the fold-aware lazy layout and adapts to available width.

A first creative enters the grid only after loading and while its organic
anchor's insertion edge is below the viewport. If it arrives after that edge
has entered the viewport, the slot is skipped for the current feed identity so
loading it cannot move visible content. A fitting replacement can fill an
existing reservation while visible; a taller replacement waits until its
insertion edge is below the viewport before the reservation grows. Native media,
headline, advertiser, and action are registered with Google's `NativeAdView`;
the SDK handles clicks and impressions. The visible Ad label and reserved
AdChoices area distinguish advertising from organic content. There is no
application-owned click overlay, simulated impression, or fabricated production
ad.
The renderer uses the same width-based layout calculation for SwiftUI's fitting
pass and the native asset frames. Multiline text, optional assets, and Dynamic
Type contribute to the host height. Before admission, it measures the complete
creative at the anchor width and current text size; the layout identity also
includes feed scope, session reset generation, viewport width, and locale.
An admitted slot retains its measured minimum height through lazy remounts and
creative expiry. Expiry removes the creative immediately, leaving an empty
reserved shell only for slots already admitted. A replacement that fits the
reservation can render without shrinking it; a taller replacement waits until
the insertion edge is below the viewport before the reservation grows. The
renderer associates the ad only after the host has finite, nonzero bounds
strictly containing every registered asset, without overflow tolerance. A text-size or width change that requires
more height defers registration until the host fits again. This addresses the
reported “Advertiser assets outside native ad view” warning without clipping
assets or disabling Google's validator.

Scheduled rows keep a 360-point ad height estimate for masonry column assignment
even before a slot fills. A never-admitted no-fill slot renders no blank cell,
though the estimate can leave uneven column tails.

Scrolling near the end requests another page. A Load More button supports
short content; failures offer Retry, and pull to refresh starts a new snapshot.
The feed stops at the catalog's end and never repeats entries to manufacture
an endless ad stream. Repeated cursors stop loading; catalog-key deduplication
retains the newest received revision. Generation and account checks discard
stale responses. Server search is debounced 275 ms.

## SDK and configuration

- Google Mobile Ads 13.11.0 and User Messaging Platform 3.1.0 are Swift Package
  dependencies linked to the app target. They are separate from FCM.
- Debug: `EXPLORE_ADS_ENABLED=YES`, `EXPLORE_ADS_TEST_MODE=YES`, Gatherory app ID
  `ca-app-pub-4218523458506277~8970323130`, and Google's dedicated native test unit
  `ca-app-pub-3940256099942544/3986624511`. The real app ID lets UMP fetch Gatherory's
  published messages while the sample unit returns test ads. Debug rejects live
  native units; the complete Google sample app/unit pair remains a supported test.
- `-BlueprintSearchVisualFixture` alone loads the local visual catalog with ads
  ineligible. The separate Debug-only `-BlueprintAdsScrollVerification` run uses
  a local 40-item catalog paged 20 at a time, the Google sample app ID supplied
  as a build override, and Google's sample native unit. Blueprint actions and
  measurement are disabled for this fixture. This verification override leaves
  the checked-in Debug and Release IDs and flags unchanged.
- Release: `EXPLORE_ADS_ENABLED=YES` and `EXPLORE_ADS_TEST_MODE=NO`, as authorized
  for beta on October 23. The fail-closed guard supports only Gatherory's exact
  production app/unit pair. Wrong, blank, mixed or sample IDs fail closed.
  Preview startup/request guards remain. Provider readiness and fill still
  determine actual serving.
- SDK startup is deferred until an active Explore surface prepares ads.
  `GADDelayAppMeasurementInit` is enabled. Canvas previews never start the SDK
  or request ads. The Light, Dark, Large text, and Narrow previews in
  `ExploreNativeAdPreviews.swift` use the actual renderer with static sample assets
  and no `NativeAd` object.

UMP refreshes consent information and presents a required form before SDK
startup. Where required, the Explore toolbar exposes Privacy choices. Changing
choices discards existing inventory and prepares a new session. Google's
complete sample app/unit pair may load test inventory without a configured UMP
message; this exception requires Debug and both exact Google sample IDs. The new
Debug default uses Gatherory's app ID, so it always requires UMP `canRequestAds`
even though its native unit returns test ads. Consent/SDK preparation runs
separately from organic catalog loading.

Requests include `npa=1`, disable publisher first-party IDs, and disable
publisher privacy personalization. Account, event, attendee, query, and category
values are never added to ad targeting or SDK request metadata. Session scope
IDs are local random values. These settings do not mean Google's SDK collects
no device, network, diagnostic, or advertising interaction data.

Inventory is bounded to three cached/in-flight ads and twelve queued slots;
unowned inventory can be evicted. Ads expire at 55 minutes. A failure gets one
delayed retry. Visible loaders/cards hold leases. Covering Explore with a
Blueprint preview, idea detail or Account suspends requests and retains
unexpired inventory for the same account until the cover is dismissed. Full app
backgrounding, leaving the Explore tab, account changes, or privacy-choice
changes reset inventory and invalidate late callbacks; layout identity changes also clear measured slot
geometry. New typed queries start the result scroll at the top; page appends
retain the browsing position.

## Server dependency and rollout

The native build requires the corresponding paged catalog endpoint in
`gatherory-web-app`. GET `/api/blueprints/catalog?limit=20` opts into paging;
`cursor`, `category`, and `q` are optional. Legacy requests without these
parameters retain the complete response. The updated response adds optional
`nextCursor` and `availableCategories` fields and preserves author metadata.
No database migration is required. No server deployment was performed.

Before live advertising:

1. Publish the actual Gatherory App Store listing with `https://gatherory.com`
   as its developer website, then link that exact listing in AdMob. TestFlight
   alone is not a public supported-store listing. Check app-ads.txt verification
   after linking, then wait for the separate app readiness review to reach Ready.
2. Verify the intended production paged catalog endpoint and archived native
   candidate together. This task did not deploy the web app's existing local work.
3. Validate UMP on test devices using Gatherory's app ID and Google's sample ad
   unit: forced EEA geography on a registered UMP test device/simulator, new and
   returning choices, refusal, required privacy options, withdrawal/repreparation,
   and the US privacy-options flow. Keep debug geography/reset controls out of
   Release. Resolve any inaccurate rendered notice before live serving.
4. Recheck native asset containment, AdChoices, test creative rendering and
   interaction registration on physical devices. Do not click live ads for testing.
5. Review SDK data disclosure, App Store privacy answers, age/content answers,
   provider/transfer arrangements and the existing legal release checklist.
   No App Store privacy or age-rating submission was made in this task.
6. Make the explicit Release enablement change only after these gates pass;
   leave Debug on the sample native unit. The off switch remains available.

Only Google's SKAdNetwork ID is included; adding mediation requires separate
partner/SDK/disclosure review. No ATT prompt was introduced. Configuration and
published messages do not certify a no-tracking classification for App Store
privacy answers.

## References

- [App readiness and separate app review](https://support.google.com/admob/answer/10564477)
- [Published and unpublished apps](https://support.google.com/admob/answer/9989980)
- [Publisher verification](https://support.google.com/admob/answer/14538460)
- [Developer website and app-ads.txt](https://support.google.com/admob/answer/9363762)
- [Regional message publication](https://support.google.com/admob/answer/13651178)
- [US state messages](https://support.google.com/admob/answer/10860309)
- [Google TCF/NPA treatment](https://support.google.com/admob/answer/9760862)
- [Google setup](https://developers.google.com/admob/ios/quick-start)
- [Native ad loading](https://developers.google.com/admob/ios/native)
- [Native asset registration and AdChoices](https://developers.google.com/admob/ios/native/advanced)
- [Native ad size and layout requirements](https://support.google.com/admob/answer/6329638#size)
- [UMP privacy flow](https://developers.google.com/admob/ios/privacy)
- [SDK data disclosure](https://developers.google.com/admob/ios/privacy/data-disclosure)

## October 22 setup follow-through validation

Landing legal tests passed (5/5); the Astro static build passed (26 pages).
The normal build reports existing marketing-image recapture warnings; no asset
files or generated status report were included in the deployment. The publisher
file is byte-identical in source/build output. Vercel production is READY at the
landing commit above; Safari verified the live policy date/disclosure and the
publisher row. AdMob publication, partner settings, native-unit ID and app review
status were inspected in the owner's signed-in Safari session. No payment data
or identity document was changed.

Native verification passed with Xcode 27.1:

- Three `ExploreAdConfigurationTests` methods passed, covering disabled/enabled
  Release, exact IDs, malformed/missing/sample/wrong/test-mode rejection, both
  Debug sample-unit configurations, and the sample-app-only consent exception.
- Debug and Release simulator builds succeeded. Build products were inspected:
  Debug has Gatherory app ID + sample native unit, flags YES/YES; Release has
  Gatherory app ID + production native unit, flags NO/NO.
- Derived data/results: `/tmp/gatherory-admob-release-gate-derived`.
  Focused command: `xcodebuild -quiet -project Gatherory.xcodeproj -scheme Gatherory
  -configuration Debug -destination 'id=744EFCA0-3C99-4581-9B94-DE817918F92C'
  -derivedDataPath /tmp/gatherory-admob-release-gate-derived
  -only-testing:GatheroryTests/ExploreAdConfigurationTests test`.
  Generic simulator builds used the same project/scheme/derived path with each
  configuration and `-destination 'generic/platform=iOS Simulator' build`.
- Xcode emitted environment `invalidDigitCount(94232)` diagnostics, but the test
  process exited successfully and all three focused methods passed.
- `git diff --check` passed in the native, server and landing repositories.

Actual device consent, ad fill and validator acceptance remain open; these
compile/configuration checks do not establish those outcomes. No physical-device
or new TestFlight release is claimed.

## October 23 native scroll verification

The Debug-only `-BlueprintAdsScrollVerification` fixture uses the local
40-item catalog in 20-item pages and Google's sample app/unit pair. The current
source suite passed **38 tests** (35 unit and 3 UI; zero failures or skips) in
`/tmp/gatherory-ad-scroll-final.xcresult`. The UI run covered Light and Dark
sample-ad browse, pagination from items 1–20 to 21–40, preview return, and
ads-disabled card geometry in both appearances. Dark appearance also checked
the native ad's natural height after an accessibility XXXL Dynamic Type
remount.

The eight focused placement-policy tests cover late initial fills, retained
geometry after creative loss, fitting visible replacements, taller replacements
admitted only below the viewport, width reflow validation, and identity reset.
Screenshots are in `/tmp/gatherory-ad-scroll-final-shots`. The inspected Light
and Dark sample-ad screens both showed the SDK validator result **“No
implementation issues found”**. The accessibility-size creative retained its
full multiline text without horizontal overflow.

A final ad-arrival follow-up passed **9 tests** with zero failures or skips in
`/tmp/gatherory-ad-arrival-final.xcresult`. In Light and Dark, it records a
visible organic card's x/y position and width/height before scrolling as a
prefetched sample ad becomes ready; the card geometry remains stable. The run
also covers all eight placement-policy tests after the stale geometry-identity
guard landed. These checks overlap with the 38-test suite and are not an
additional count of unique tests.

This remains simulator/sample-inventory evidence. The Google sample app ID
uses its consent exception; it does not validate Gatherory's UMP messages, the
production authenticated catalog, physical-device scrolling, the 55-minute
expiry path, ad clicks, or frame rate. The Release build result is tracked in
[native testing verification](testing-verification.md).
No Release enablement or checked-in Debug ID change was made for this run.

## Historical integration validation

The iPhone Duo simulator Debug build succeeded with Xcode 27.1. Web TypeScript
type checking, generated contract consistency, and English/Spanish localization
checks passed. No tests were added or run. Live ad fill, consent presentation,
click/impression registration, and physical-device scrolling remain runtime
acceptance items; a successful build does not establish those outcomes.

After the October 22 asset-containment fix, the iPhone Duo simulator Debug build
succeeded again. The warning has not yet been rechecked with Google's validator
on the physical phone; build success does not confirm validator clearance.

Canvas could not complete the visual pass: the preview host repeatedly crashed
with `EXC_BAD_ACCESS` in JIT/SwiftUICore frames, including after isolating the
preview declarations and choosing the iPhone Duo preview device. No successful
render or visual approval is claimed. The ordinary simulator build succeeds.
