# Event ideas → Schedule

October 30, 2026. Native source change; no backend rollout or TestFlight upload
is implied.

The consumer flow is **suggest → weigh in → schedule → attend**. Personal
Love It/Maybe/Pass responses express preferences. They never approve a proposal,
create an event automatically, or become an attendance response. Eligible
planners can schedule before everyone has responded; there is no majority rule
or deadline in this slice. Guest voting remains deferred.

## Ideas shortcuts — November 2, 2026

Ideas now includes the viewer's personal Liked filter. Long-press Schedule opens
the same date/location sheet described below; non-event Approve opens a compact
confirmation sheet, also reused by the existing detail action. Parent event
status and sharing remain separate from accepting an idea. See
[Liked and approval behavior](ideas-liked-and-approval.md), including draft-event
budget/visibility semantics and permission boundaries.

## Native handoff

Open an event idea from Ideas or its Decide detail and tap **Schedule**. The
native sheet carries the proposal's date/time and location. An undated proposal
starts its draft at the current time. Existing native date/time and location
editors change the sheet's draft only. Location is optional. Cancel, including
interactive dismissal, changes neither the idea nor Home.

Confirming Schedule records the chosen proposal and its timing together and
creates one linked Home subevent. The idea keeps its title, description, image,
media asset reference, audience, budget, attire, and personal responses. The
schedule uses the existing event/idea linkage and persistence paths; this adds
no new wire format or database schema. Repeated identical confirmation returns
the same event identity. Exact committed linked events are reused. This command
does not reschedule an existing linked event from an old proposal snapshot;
edit the scheduled event through its existing event controls.

The event-idea detail replaces Approve/Add a Date/Add to Home with Schedule and
then **View Event**. This pushes the exact linked child invitation on the native
navigation stack; system Back and the interactive back gesture return to the
same idea. The linked event remains available on Home. The scheduled idea
preview uses that child's current content and says Scheduled Event rather than
Proposed. Ambiguous, archived, deleted or inaccessible links never fall back to
the root or a sibling. Non-event ideas keep their approval actions. Legacy
chosen event ideas remain compatible with the existing reconciliation behavior;
this is not a stored-status migration.

The Schedule sheet includes compact team preference counts and the unanswered
count. These reflect the existing event-scoped eligible planners; there is no
new guest eligibility, automatic winner or requirement to wait for responses.
After scheduling, the old proposal editor is hidden. Open View Event and tap
the event content to edit through its existing native sheet, so the editor does
not reopen an older proposal over independently edited event content.

## Permissions and recovery

Scheduling requires an active host or a collaborator with Manage permission on
the root event. Contributors can propose content/dates and submit preferences;
guests and view-only members cannot schedule. Scheduling remains unavailable in
an isolated child planning scope because the event tree stops at one child level.

The request captures the exact proposal, root, viewer context generation, and
member authority. Confirmation checks them again, rejecting stale edits,
account changes, lost permissions, archived proposals, deleted roots, invalid
dates, or changes to proposal settings outside timing/location. Routine
reconfiguration of the same account does not invalidate a request. The sheet
dismisses if its captured authority/source changes. A current request rejected
by the command exposes a native retry message.

Contributors cannot revoke a scheduled event by downgrading its idea or clearing
its scheduled date. Unrelated content edits keep their existing permissions.
Personal preferences and actual invitation RSVPs remain independent.

## Verification

See the Schedule handoff section in [testing verification](testing-verification.md)
for executed checks and acceptance limits. Development acceptance now exercises
real authenticated HTTPS synchronization with two independent SwiftData clients:
contributor preference → manager receives it → Schedule → contributor receives
one linked event → repeated reconnect → verified cleanup. The clients use
separate in-memory stores within a simulator-hosted test; this is not a
two-physical-device or signed-candidate acceptance claim. The offline step saves
without synchronizing before reconnect; it does not switch device radios off or
verify process-relaunch persistence.

`IdeaSchedulingLiveSyncTests` is opt-in. Normal test runs skip it. It targets
only `https://dev.gatherory.com`, verifies the App Review and coordinator
development identities and their shared manager/contributor permissions, and
rejects unrelated pending mutations. Its credential inputs stay outside source;
a protected file referenced by `GATHERORY_LIVE_SYNC_CREDENTIAL_FILE` avoids
bearer tokens in runner arguments or environment diagnostics. Set
`GATHERORY_LIVE_SYNC_ACCEPTANCE=1` only for an intentional development run.

Cleanup reopens only the test-created proposal using the normal host lifecycle,
which unschedules its child and participation records. The contributor can then
retract the response while the proposal is open. Normal persistence writes the
cleaned compatibility snapshot and entity tombstones. Final server bootstrap
reads verified no remaining temporary ideas/events for either account. Temporary
sessions were revoked and credential files removed; production was untouched.

Current stopping point: the Schedule handoff, direct linked-event navigation,
compact team input, native cancellation/confirmation flow, permission guards,
and focused regressions are implemented. Optional guest
participation in Decide remains a separate product and authorization change;
there is no automatic winner, group deadline, or guest voting rollout here.
Two physical devices and the signed release candidate remain release acceptance
work; the available development setup had only one connected physical phone.
