# Team budgeting audit — October 30, 2026

Implementation follow-up: see [team budget safety](team-budget-safety.md) for
the subsequent fixes, synchronization contract and conflict recovery. Findings
below describe the audited behavior before that follow-up; they are retained as
the original evidence rather than presented as the current acceptance result.

## Conclusion

Gatherory has a useful planning-budget foundation: one overall cap, event
allocations, a derived free pool, and exactly one expense per cost-bearing idea.
It is not ready to treat collaborative budget changes as reliable financial
bookkeeping. Fix paid-record preservation, budget authority and allocation
atomicity before V1. Resolve silent funding failures and misleading totals in
the same release slice.

This was an audit, not an implementation pass. Luna agents investigated the
native model, native UI and server protocol separately. New isolated tests
simulate team roles and concurrent clients; no actual account budget, server
data, migration, application behavior or production deployment was changed.

## How the current model works

- Overall cap and allocations are different from costs. Increasing an allocation
  moves planning capacity; it does not record a payment. Main/child allocations
  plus the free pool should equal the overall cap.
- A positive idea estimate immediately produces an Estimated expense through
  the native idea write path. Approval changes that row to Committed. Personal
  Love It/Maybe/Pass responses do not change the shared budget.
- Scheduling an event idea moves its linked expense to the created child and
  requests an initial allocation. The requested allocation is not another cost;
  the estimate remains one ledger row.
- Estimated, Committed and Paid are mutually exclusive statuses on an expense,
  not three copies of the cost. Current totals sum all three statuses.
- Each expense belongs to one event. There is no model for who paid, partial
  payments, reimbursements, sharing an expense across people/events, or currency
  conversion. Paid is manually recorded bookkeeping, not a payment integration.

## Findings and simulated evidence

### High: ordinary idea edits can erase paid bookkeeping

Simulation: approve a $40 catering idea, mark its linked expense Paid, then edit
only the idea's note. The same expense is rebuilt as Committed. Mark it Paid
again and archive the source idea: the expense disappears and Paid total falls
to zero. No refund, payment reversal or financial edit was requested.

`PlanningWorkspace.reconcileExpense` derives status only from idea approval,
and removes the row for passed/archived ideas. It does not preserve a paid row
or ask for a financial-history decision.

Evidence: `TeamBudgetAuditTests.paidExpenseSurvivesIdeaEdit`, with two known
issues; `Gatherory/App/PlanningWorkspace.swift:2154–2184`.

Recommendation: preserve paid records on nonfinancial edits and idea archival.
Treat changes to an already paid amount as an explicit adjustment; do not replace
actual payment information with a new estimate. Unscheduling a linked event must
also account for its existing costs before removing them.

### High: allocation authority is inconsistent across entry points

The allocation screen requires management authority on the root and target.
The full root-event editor instead uses the broader `canManageMainEvent` gate,
shows its Budget settings, and calls `updateWorkspaceBudgetCap` without a
manager check. Simulation confirms a contributor fails the allocation-screen
policy but the root editor's budget command accepts a cap resize from $100 to
$150.

Server source review shows the same mismatch: an active root contributor maps
to an editor in native sync, and editor workspace/event writes have no separate
budget-field manager check. Scoped-child event writes are more restrictive.
This root write was not exercised against a live server in this audit.

Evidence: `TeamBudgetAuditTests.contributorRootCapPolicyMismatch`;
`BudgetView.swift` (`BudgetAllocationPermissionPolicy`),
`HomeView.swift` (`canEdit`), `EventEditorView.swift:452,759`,
`PlanningWorkspace.swift:577`, server
`src/server/sync/repos/native-sync-legacy.persistence.ts:263–304,442–555` and
`native-materializer.persistence.ts:592–630`.

Recommendation: enforce budget-management permission in domain commands and at
the server, including changes arriving inside an otherwise legitimate event
edit. Keep ordinary event/content editing separate from cap/allocation powers.

### High: independent offline allocations can consume the same pool

Simulation: overall cap $1,000, main allocation $800, free pool $200, two enabled
children at $0. Two separate manager accounts start from the same archive. Each
validly assigns $150 from the observed pool to a different child. Combining the
actual child entity updates produces $800 + $150 + $150 = **$1,100 allocated**.
The free-pool calculation clamps to zero rather than exposing the deficit.

The merge counterexample is reproduced locally using the native archive merge
code. Server acceptance of this particular race was not tested. Source review
finds no server aggregate allocation guard: normal native budget records have
no base version, and push processes each mutation in its own transaction. A
transfer represented as multiple cap updates can also partially succeed.

Evidence: `TeamBudgetAuditTests.concurrentChildAllocationMerge`;
`WorkspaceBudgetRules.swift`, `WorkspaceArchiveV1+Sync.swift`,
`WorkspacePersistence.swift:716–730`, `WorkspaceOutboxWriter.swift:135–150`, server
`native-sync-legacy.persistence.ts:349–435,561–571,725–735`.

Recommendation: represent an allocation change as one idempotent server command
with management checks, a shared budget version and a transaction covering the
source/destination balances. Validate conservation under a lock. Offline clients
can retain the draft/intent, but reconnect must resolve a conflict for the whole
transfer rather than accepting independent last-write-wins balances.

### High: Schedule can silently drop a requested allocation

Simulation: an event idea requests a $150 budget under a $100 overall cap. The
normal Schedule confirmation succeeds and creates a child with **$0 allocated**.
The cap is not exceeded, but the requested funding was not honored or surfaced
as a failure. The new child/idea are already committed.

`scheduleEventIdea` ignores the Boolean returned by `allocateInitialBudget`.
The ordinary event editor has an affordability validation; the idea Schedule
handoff does not provide the equivalent result boundary.

Evidence: `TeamBudgetAuditTests.oversizedScheduledEventBudget`;
`PlanningWorkspace.swift:2019–2028`.

Recommendation: validate funding before committing Schedule, or explicitly let
the organizer choose an unfunded event. Preserve their draft and never silently
replace a requested amount with zero or increase the overall cap automatically.

### Medium: “Total Spent” is a forecast, including unapproved options

Simulation: add catering alternatives at $60 and $70 under a $100 cap. Nothing
is approved or paid, yet the current remaining figure is **−$30**. This follows
the existing tested estimate policy; the problem is that the UI calls the sum
“Total Spent” and labels individual forecast totals “spent.” The event idea
editor also says an estimate becomes tracked after approval, although it is
tracked immediately.

Evidence: `TeamBudgetAuditTests.alternativeEstimatesAreNotPaidOrCommitted`;
`BudgetView.swift` (`totalCard`, `budgetSignal`, `budgetRow`),
`EventEditorView.swift` cost summary, `IdeasView.swift` budget/cost footer.
The web calls its comparable amount tracked cost and sums expense rows only.

Recommendation: use clear Planned/Committed/Paid figures. Treat candidate
estimates as options rather than money already spent. Decide whether remaining
budget subtracts committed obligations or the full forecast, then use that rule
and wording consistently. There is no formal mutually exclusive option group
in the current idea model, so do not infer alternatives from their titles.

## What worked and what needs a product decision

- Single-client affordable transfers conserve the cap, reject negative transfer
  amounts and insufficient funds, and distinguish no allocation from zero.
- A linked idea maintains one expense identity; scheduling reassigns its cost
  to the child rather than counting the idea and expense twice. Declining an
  unpaid idea releases its planned cost. The paid case above is different.
- The host can open an allocation editor, edit a local draft, cancel, reopen
  the unchanged allocation, and return directly to the same management screen.
- A view-only collaborator can read the team budget while allocation controls
  remain disabled. Guests do not receive planning-budget access in the reviewed
  permission paths. Child/sibling isolation has existing server coverage, not
  a new live/database run in this audit.
- Contributors can currently approve non-event ideas and edit costs. Decide
  whether that should also authorize a financial commitment or a Paid change;
  there is no separate spending-approval workflow today.
- Raw `replaceExpenses` accepts negative local values; the new probe records
  this as a known issue at a trusted mutation boundary. Normal money fields
  sanitize input, and the database has `event_expense_amount_check >= 0`.
  This is not evidence that negative expenses can persist remotely.
- Ordinary native fields limit entry to two fractional digits. Alternate API
  payloads are less strict and database amounts use `numeric(14,2)`. Define
  rounding/precision behavior before adding importers or multiple currencies.

## Verification

New files: `GatheroryTests/TeamBudgetAuditTests.swift` and
`GatheroryUITests/TeamBudgetAuditUITests.swift`. All new data is synthetic and
ephemeral; this pass does not alter actual team budgets. Known issues deliberately
assert the desired invariant, so the test report must not be described as proof
that budgeting is correct merely because the runner accepts expected failures.

The screenshot-free native host Light and view-only Dark UI scenarios passed
in `/tmp/gatherory-team-budget-audit-final-20261030.xcresult` (27.671 and 14.821
seconds). They cover navigation, draft cancellation and read-only controls;
they do not submit a committed allocation or exercise a real sync race.

The existing web overview/contract/ordering/identity unit selection passed nine
tests in four files: `/tmp/gatherory-team-budget-web-unit-20261030.log`.
No opt-in database suite, live budget mutation or server workflow was run.
The backend findings remain source-backed until those isolated integrations
are added. See [testing verification](testing-verification.md) for the final
native unit/known-issue counts and artifacts.

## Build order

1. Preserve Paid entries and amounts across idea edits/withdrawal, with explicit
   adjustment semantics.
2. Apply one manager-only budget policy to all editors and sync paths.
3. Add atomic, versioned, idempotent allocation commands and conflict tests with
   two independent clients, including partial-delivery retries.
4. Make Schedule funding failure explicit and reversible before commitment.
5. Clarify planned versus committed versus paid totals and the treatment of
   unselected options; then revisit UI polish.

Payer splits, reimbursement, actual payment collection and foreign-exchange
conversion remain separate future features rather than requirements for this
native V1 audit.
