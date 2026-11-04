# Movie Night onboarding

## Simple contextual primers

Explore and Decide reuse the welcome screen's Gatherory mark, centered
large-title heading, leading blue feature symbols and short descriptions, with
one native capsule **Continue** button. They are presented through native
`fullScreenCover`, so the content occupies the same edge-to-edge canvas as the
welcome screen instead of a rounded sheet with a grabber. The original welcome
screen remains unchanged.

`FeaturePrimerView` uses the existing 108-point brand asset, 34-point system
large-title style at the default text size, 24-point header spacing, 40-point
header-to-features separation, 24-point row spacing and 24-point side margins.
The 44-point icon column aligns the rows; the native Continue action is centered
and content-sized. Existing adaptive background, primary/secondary text and blue
accent tokens are preserved, with no new palette, gradients, containers or
animation. The available view height controls spare space; longer translations
and larger text can scroll above the opaque footer. There are no guessed device
coordinates or fixed screen-height assumptions.

The Apple design skill review identified the previous oversized utility symbol
and sheet chrome as the main visual mismatch with the supplied welcome reference
(design judgment). The changes follow `typography.md › Conveying hierarchy`
(“Adjust font weight, size, and color as needed”) and `layout.md › Visual
hierarchy` (“Group related items”), while keeping the requested brief,
noninteractive education. This is visual refinement, not an appearance or
contrast certification; system appearance settings remain authoritative.

Decide explains **Pass** (left), **Maybe** (up), and **Love It** (right). There is
no practice card, demo gesture, feedback state, or extra date lesson. Reading or
closing it does not record a preference. The real Decide deck still supports
swipes and its existing choice buttons. Search keeps its three brief discovery
features and removes the repeated introductory paragraph. Both primers keep the
existing first-tab timing and account-scoped dismissal/replay rules.

## First run and Explore entry

After authentication, account recovery, invitation routing, and session
preparation, onboarding presents the original **Welcome to Gatherory** screen:
the Gatherory mark, invitation and planning features, and collaboration copy.
This is the same `OnboardingWelcomePrimer` used by the classic flow, extracted
without redesigning its native layout. Continue opens Movie Night's **Start
tour** and **Skip** choice. Decide and Search education are not shown here.
No discovery phase or workspace is created before the Start tour action.
Skip completes onboarding without creating a workspace. Start
records an account-scoped entry phase in `MovieNightTourDiscoveryStore` and opens
the ordinary Events/workspaces tab with the guide prompting **Tap Explore**.
Starting the tour does not create or install a workspace.

The persisted discovery phase is keyed by canonical account ID at
`movieNightTourDiscovery.<accountID>` and is one of `chooseExplore` or
`chooseMovieNight`. Tapping the normal Explore tab moves to the second phase and
shows the regular native Explore screen: its usual header, profile, search,
content filter, and masonry feed remain in place. Cached or online catalog cards
can still appear, while the bundled Movie Night entry is prepended and
deduplicated against the feed. Movie Night remains available if the catalog
request fails or the device is offline.

During this entry, the controls and other cards remain visible but disabled;
only the Movie Night card can be selected. The checked-in
`movie-night-blueprint.v1.json` provides its artwork and content. The card gets a
decorative accent border without covering its accessibility element, and its
measured `.movieNightBlueprint` target lets the NPC pointer identify the actual
card. The normal Explore tab is also measured and highlighted for the initial
**Tap Explore** prompt. This uses the ordinary Explore screen rather than a
separate tour-only mock feed. Scrolling the feed remains available.

The overlay shows only the current instruction and navigation, with no face,
heading or minimize control. Its footer presents **Previous**, centered **Skip
tour**, and **Next** as separate native capsule buttons with full-size hit
targets; each action is gated by the current step. Previous on Explore returns to the Events
prompt. Before card selection, Next stays disabled because no workspace action
has completed. Skipping before selecting the card clears entry state, completes
the tour without a new plan, and reveals normal workspace or Explore behavior.

Selecting Movie Night is the point where a workspace is created. The coordinator
validates the persisted Explore phase, creates a normal locally owned workspace
from the bundled snapshot, saves it through the ordinary persistence and outbox
path, and records the actual IDs needed for the guide. A save failure leaves the
selection available for retry. The new workspace belongs to the signed-in
account and can be deleted from Events.

The lesson includes a snack idea (`Popcorn bar`), a schedulable event idea
(`Watch the movie`), and a child activity attached to the Movie Night event. The
workspace guide follows real app state: the snack must be loved and approved and
the event idea must be scheduled. It never fabricates votes or schedule state.
Its targets are the exact idea IDs recorded at creation, so missing or deleted
targets cannot produce a false success claim. The `-ClassicOnboarding` launch
argument preserves the classic `OnboardingView` flow.

## Guide backdrop and Explore spotlight

The guide floats over the existing content with a rounded, feathered native
material backdrop. Continuous 32-point corners and a soft outer blur surround a
cyan, lilac, pink and peach gradient wash. Thick native material and a strong
adaptive system-background wash protect the padded text area; only the extra
area outside the rounded core fades. This prevents bright or busy artwork from
bleeding through the instructions or footer. The active Skip tour text uses
primary foreground contrast, and workspace arrows draw above the blur. The
words and buttons stay sharp; there is no card border or shadow. This is a
live system backdrop, not a screenshot or duplicated feed. Reduce Transparency
uses an opaque rounded system-background surface with the same color wash for
readable instructions, without the blur.

On the initial Tap Explore step, a noninteractive dimming overlay leaves the
measured native Explore button and guide clear. A blue outline and arrow identify
the actual tab. Overlapping cutouts are unioned, so a nearby guide cannot dim the
target again. The overlay is hidden from accessibility and passes taps to the
real controls. It disappears when Explore is selected; the Movie Night border and
pointer then guide selection as before. No screen layout or auth flow changes.

## Pointers through the planning lesson

The coach points to the actual native Decide tab when the lesson asks for input,
the Ideas tab after Love It (or when returning to approval/scheduling), and Home
after scheduling. Once the correct tab is open, it points to the exact snack
or movie idea, decision card, or native Ideas filter. Instruction text names the
same next control. Earlier recap instructions have no active target, and no
pointer is drawn for missing/offscreen targets.

Native tabs are measured from the visible UIKit tab bar that contains the
localized target label. Their positions are not guessed from screen widths or
tab order. Measurement is deferred outside layout, cancelled on teardown, and
projected into the same coach coordinate space as card anchors. The dialog stays
inside the content safe area while the pointer can reach the measured native
tab bounds beyond it. Workspace tabs receive an arrow without a clipped outline;
idea cards and filters retain their focus outline.
Outlines and arrows do not intercept taps. Native-tab decorations are hidden
from accessibility; the original tab remains the accessible control. The
inside-dialog coordinate diagnostic exists only in the isolated Debug harness.
Action-driven progress, Previous/Next, and Keep/Remove stay intact. The guide
stays available across tabs; Skip tour and Account's Redo tour provide exit and
replay without a separate minimize/resume control.

## Account-bound progress and replay

### Developer-only full onboarding replay

In a development-configured **Debug** build, Account → **Developer** → **Redo
onboarding** restarts the actual launch onboarding: the original welcome,
Movie Night Start/Skip choice, and the usual tour or return to the app. This is
separate from the normal Redo tour action. It keeps the signed-in account,
existing events, and authentication credentials; no account deletion or login is
required.

The action clears only the current account's local tour/discovery and tab-primer
education keys. Existing practice events are retained. The request is transient
and does not mark the server account incomplete. The launch container accepts
it only for the current prepared authenticated account after normal routing has
resolved to the app or a completed remote account. Sign-in, guest import,
recovery, invitations and shared-blueprint routes keep priority. Signing out or
changing accounts cancels the in-memory replay; completing or skipping uses the
existing onboarding completion path.

The action, request listener and replay state are compiled out of Release builds.
Configured staging/production builds hide the control as well. The gate uses
configured `APP_ENVIRONMENT`, so the ordinary development Debug configuration
can retain tools while `SIMULATE_PRODUCTION_FLOW=YES` exercises real-account auth
routing. That simulation still controls auth behavior; it does not enable tools
in a production-configured or Release build.
See the [developer replay verification](testing-verification.md#developer-only-full-onboarding-replay--november-3-2026).

### Normal tour replay

`MovieNightTourDiscoveryStore` tracks the pre-workspace Events → Explore entry.
`MovieNightTourStore` separately records
`movieNightTourProgress.<accountID>` with `installedWorkspaceID`, `snackIdeaID`,
`eventIdeaID`, and `step`. Progress contains IDs and step only, not event content,
credentials, votes, or helper identity. Both stores are scoped to the canonical
account ID; account switching cannot resume another person's route or lesson.

The **Redo tour** action in Account shows the same original welcome screen and
Start/Skip prompt. Starting an
unfinished tour visits Explore first, then resumes the available owned workspace
and preserves its edits. Starting after completion, or when the earlier lesson is
unavailable, visits Explore first and creates a fresh local copy only after Movie
Night is selected; it leaves the old workspace untouched. Skip before card
selection creates no new plan and clears the entry phase. Account deletion clears
only that account's discovery phase, tour progress, and primer dismissals.

The entry NPC and workspace guide use a full-width Previous / centered Skip /
Next footer. Workspace-guide Next changes to **Finish tour** when the real
completion conditions are met; it never advances using a fake action. **Skip
tour** and successful completion open the Keep/Remove choice for an instantiated
lesson. The workspace overlay uses measured targets on the Ideas filter,
matching idea card, and current Decide card. The entry pointer also targets the
native Explore tab and the highlighted Movie Night card using measured frames;
neither decoration occludes the control's accessibility element. The guide does
not move VoiceOver focus and respects Reduce Motion and Reduce Transparency. The
pre-tour screen explains the practice event can be deleted from Events.

## Keep or remove the practice event

Finishing the lesson, or choosing Skip tour after its workspace was created,
opens a native confirmation: **Keep event** or **Remove event**. Keep completes
the guide and leaves the event, activities, ideas, and saved choices intact.
Remove deletes only the exact account-bound tour workspace through the normal
local persistence/outbox transaction, returns to Events, and completes the guide.
The event title is not used to locate it, so another event named Movie Night is
unaffected. Intro/discovery Skip before card selection has no event to remove and
does not show this prompt.

The removal action rechecks the active account, stored tour workspace ID, current
host/manage participation, lifecycle, and normal delete authority when the person
confirms. A failed save restores the original library order, selection, workspace
records, and pending changes; the guide stays available with a retry/keep message.
A local-only create is coalesced away; an acknowledged server workspace receives
a durable scoped delete for reconnect. Earlier or other workspaces are retained.
Choosing either option completes the guide; already seen tab primers do not repeat.
Redo tour can create a fresh local copy after removal.

## Welcome and first-visit tab primers

Only the general welcome content precedes the tour choice. **Search** presents
on the first visit to **Explore**; **Decide** presents on the first visit to
**Decide**. This applies during guided discovery/planning as well as ordinary
use, after account onboarding is complete. Native primer sheets take priority
over guide interaction, and dismissal returns to the same real tour step.
The Decide guide overlay is suppressed while its primer is open.

Each dismissal is stored separately per account and primer, so switching tabs
does not repeat education. Explicitly starting/replaying the lesson resets only
that account's tab-primer dismissals, ready for its first contextual visits;
viewing welcome or skipping the tour choice does not consume them. The classic
onboarding override retains its original event-creation step.
Search explains blueprint/idea search, the default All
content filter and type filters, and adding an idea to the person's own event.
The primer is local UI and does not wait for a network response.

The Explore/Search primer uses the welcome screen's visual hierarchy: a centered
accent search symbol, centered title and introduction, leading icon-and-text
feature rows, and a native bottom action. It keeps the existing Search/filter/add
education and scrolls on compact windows. The action has a solid footer so text
does not show through behind it; the final feature can scroll fully above it.
Its first-visit timing is unchanged. See
[Explore primer verification](testing-verification.md#explore-primer-in-the-welcome-style--november-3-2026).

## Acceptance status

The restored-welcome follow-up supersedes the earlier interpretation that put
Decide and Search before the tour. Current coverage checks the original welcome,
first-visit tab primers, guide resumption, the full planning/Search journey and
classic onboarding. See the
[restored welcome results](testing-verification.md#original-welcome-and-contextual-tab-primers--november-3-2026).

The preceding instructions-only/pill-button follow-up passed three focused backdrop
tests and two native Duo flows in the current default appearance. This includes
the full guided planning journey and keyboard Search, plus pointer navigation.
Captures were checked for removed chrome, visible capsule buttons, gradient and
arrows; the same shared backdrop covers discovery and workspace guidance.
See [instructions-only results](testing-verification.md#instructions-only-tour-with-pill-buttons--november-3-2026).
This follow-up did not rerun the full phone-size or appearance matrix.

The preceding navigation-compatibility source has a passing full real-planning and keyboard-search run on
iPhone Duo / iOS 27.1, using its 466 × 678 point portrait app window. This device
uses a native vertical toolbar rather than a tab bar. See the
[Duo verification and limits](testing-verification.md#movie-night-tour-on-iphone-duo--november-3-2026).
Earlier three-iPhone simulator results below remain useful historical evidence,
but predate the latest source and do not establish its behavior on those sizes.
The Duo run uses the current default appearance; no appearance matrix was run.

The earlier November 3 planning-pointer pass checked Decide/Ideas tab coordinates,
native taps, a real Love It response, and the subsequent filter/card target. It
predates the latest Duo source and is historical evidence, not a current-source
acceptance claim.
See [planning-pointer results](testing-verification.md#planning-tour-tab-pointers--november-3-2026).

The earlier November 3 backdrop/spotlight follow-up passed 11 focused unit tests
and three distinct native UI cases. It predates the latest Duo source and is
historical evidence. See the
[spotlight verification record](testing-verification.md#feathered-guide-backdrop-and-explore-spotlight--november-3-2026).
The broader November 2 results below describe that earlier source snapshot.

An earlier November 2 source snapshot passed **1,269 unit tests** (one opt-in live test
skipped) and **eight distinct native UI cases** across the full run and corrected
search-test rerun. Its Light/Dark checks covered the measured native Explore target,
text navigation, regular feed with disabled controls, outlined Movie Night as the
only selectable card, real voting/approval/scheduling, replay, Keep/Remove,
classic onboarding, and restored native search typing/scrolling after the guide.
The first full run had one stale search-placeholder test selector; the corrected
case passes without an app behavior change. The full bundle alone was not green.
See [current artifacts and acceptance limits](testing-verification.md#regular-explore-tour-and-text-navigation--november-2-2026).

The latest Duo record includes one passing full UI method and no failures. The
current-source standard iPhone 18 Pro regression also passes 24 focused unit
tests and two UI methods for repeated entry and native navigation/filter
pointing. See the verification log for exact artifacts and limits. English/Spanish
coverage remains 1,879 strings; historical generic Simulator Release results
predate this source.
Signed-device, minimum-iOS, and authenticated reconnect acceptance remain
separate release checks.
