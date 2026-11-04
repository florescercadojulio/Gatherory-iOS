# Event management from Home

Updated November 2, 2026. Native source only; nothing uploaded or deployed.

## Entry points and navigation

Workspace navigation has Home, Ideas and Decide, with no Manage tab.
Each accessible event card in Cards and Overview has a full-width Manage
footer beneath its details, separated by a divider and ending in a chevron.
The card body still opens the invitation; only the footer opens management.
It is a separate button, does not select a different event, and has at least
a 44-point touch target. Floating pills and card-context management shortcuts
were removed. Existing share, edit, export and removal menus remain.

Management pushes onto the existing native navigation stack. It has no modal
sheet, nested stack, detents or Done button. Native back navigation returns to
Home. The event name stays in the toolbar while moving between sections.
The invitation toolbar has no Manage action; use the preceding Home card's
Manage footer before opening the invitation.
Vertical cards reserve footer height within their existing bounds. Overview
keeps image, details and footer in one outer rounded card.

The footer opens the existing `ManageView` dashboard directly: budget, guests,
collaborators, approval review, tasks, updates and planning guidance. There is
no intermediary menu or section list. The dashboard is pinned to the supplied
event, ignores Home's current event when resolving its contents, and has no
event switcher. Manage has no editing gear. Open the event invitation and tap
its title, date or location to edit in a native sheet. Main events retain their
field-specific editors; child events open the existing event editor with the
exact child captured. Cancel returns to the same invitation, with native Back
returning Home. Child editors close when their event, account or permission
changes; missing children cannot fall back to creating a new event. Read-only
planners and invitation guests do not receive editable content controls.

**Manage → Updates is event-specific.** A child event's Manage footer opens
only that child's announcements and planning notes, independent of Home's
selected event. Main-event and sibling-event updates are excluded; the main
event feed is not a workspace rollup either. Legacy notes without an event ID
belong only to the main event. The Updates audience choices (including All)
filter recipients within this event, not across events. Posting uses the same
event ID. Switching events clears the previous feed and ignores late responses
for the previous event. Both native transport/controller validation and the
server query enforce the exact event ID; no feed-scope behavior change was
needed during the October 30 audit.

Budget is one navigation destination. It opens the managed event's budget
first. For an unscoped workspace, **All event budgets** switches the displayed
scope inside that same screen; **This event’s budget** restores the original
event. It does not push another Budget screen, so native Back returns directly
to the same Manage dashboard. Scoped event workspaces cannot switch to a root
overview. Event and workspace projections retain their existing data rules.

## Scope and recovery

`EventManagementAccess` requires a visible direct event, active planning
participation, a valid management summary and a readable planning scope.
Guest-only/invitation projections, ideas, unknown/detached/archived children
and deleted roots cannot open it. `EventManagementView` captures its fixed
reference, workspace ID and authentication generation once. It verifies the
current account or local planning principal and rechecks destination access
before rendering. Invalid scope pops the view or closes its editor; an invalid
initial destination cannot fall back to root-event management.

Management uses local account identity rather than notification/announcement
authorization. A token-matched offline account can read its saved management
data, including older participants resolved by the configured account's email
when their user ID is absent. A different configured account, a participant
linked to another user ID, an unconfigured preview identity or a mismatched
local guest profile is rejected. Remote announcement and push authorization
remain unchanged. Initial scope capture shows a neutral loading indicator
instead of briefly claiming the event was removed.

Task notifications select Home and push the matching event's Tasks section
inside Home's navigation stack. Announcement notification presentation remains
separate. Legacy management dashboard types remain available to tests but have
no workspace tab entry.

## Verification

The October 30 editing update passed 16 unit tests and two native UI methods
covering Light/Dark main/child content editing and guest restrictions. Manage
has no editing gear. See Event editing from invitation content in
`testing-verification.md` for the Device Hub observation and acceptance limits.

The October 30 scope audit passed 33 announcement/note unit tests and one native
main/child Manage → Updates navigation test. See Event-specific Updates audit
in `testing-verification.md` for artifacts and the synthetic/live-data boundary.

Two Luna agents handled direct dashboard reuse and regression updates. Focused
unit/build results and current acceptance limits are
recorded in `testing-verification.md` under Event management from card footers.
The screenshot-free native footer test passed for main/child events in Cards
and Overview, dashboard/Collaborators navigation and native back to unchanged
Home context. Guest and invitation-toolbar UI cases remain compiled-only.
Local identity regressions cover cached offline accounts, unlinked email-only
participants and account/profile mismatch denial; see the Manage availability
section of the testing guide. The focused Budget regression runs main/child
Overview → Manage → Budget, repeated open/back and same-screen scope changes;
its actual results are recorded under Budget back navigation in the testing
guide. No screenshot attachments are requested by that test.

Native swipe gestures, the full visual Light/Dark matrix and physical
notification handoff remain acceptance work. No server, schema, dependency,
commit, push or deployment is part of this change.
