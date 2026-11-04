# Team budget safety

Implemented October 30, 2026, following the [team budget audit](team-budget-audit-2026-10-30.md).
Mobile acceptance completed November 2, 2026; see [executed checks](testing-verification.md).
This is source work awaiting an explicitly authorized rollout; it has not been
deployed or uploaded to TestFlight.

## Budget meaning and permissions

The overall cap limits allocations across the main event and its children.
Unallocated money remains in the free pool. An allocation is planning capacity,
not a payment. Moving capacity does not create an expense.

Budget totals are labeled **Tracked cost**, with separate Estimated, Committed
and Paid rows. The **After planned costs** figure subtracts every tracked cost,
including unapproved estimates. Candidate ideas remain separate estimates;
Gatherory does not infer mutually exclusive options from their names. Personal
votes do not spend money or change the team budget.

Changing a cap or allocation requires management authority on the main event
and on each affected child. Contributors can edit ordinary event content but
cannot use its editor to change shared caps. The native domain, editor controls
and server mutation boundary enforce this distinction. Scoped child views
cannot transfer money from other events.

## Paid records and scheduling

Once a linked expense is Paid, editing its idea does not replace its paid amount
or status with the new estimate. Passing or archiving the idea keeps that paid
record. Unscheduling/deleting a child rehomes its paid rows to a surviving event;
if the source idea was removed, its link is cleared. Expense replacement keeps
omitted paid rows and rejects a replacement containing negative amounts before
changing the existing ledger.

This does not add a payment correction, refund, reimbursement or split-expense
workflow. Paid is still manual bookkeeping. An explicit adjustment feature is
separate work; an estimate edit must not silently rewrite a recorded payment.

Schedule checks requested initial funding before changing the idea or creating
its linked child. An unaffordable request fails with the date/location draft
still in the sheet. The error identifies insufficient available funds. Zero or
absent funding is not substituted for a positive request.

## Atomic allocation synchronization

Existing account-scoped native sync carries one `budget_transfer` entity whose
payload operation is `replace_budget`. It includes the complete overall cap and
main/child allocation vector in integer cents, a stable mutation ID and an
expected shared budget revision. Explicit JSON null clears an optional cap or
allocation. Money with unsupported fractional precision is not silently rounded.

The server serializes a root's budget changes, verifies management authority,
requires the exact canonical event set and validates allocations against the
cap. Every balance, compatibility snapshot, change record and idempotency receipt
commits in one transaction. The budget has its own revision, so an ordinary
content edit in the same push does not cause a false budget conflict. A stale
revision changes no balances. Repeating a delivered mutation returns its receipt.

Ordinary native event/archive updates omit budget fields. The server retains
canonical budget values when those fields are absent and rejects direct legacy
budget replacements. Initial workspace creation remains a bootstrap path.
`budget-atomic-v1` advertises client support; older native clients must upgrade
before consuming a scope with the new budget entity.

The outbox delivers one budget command per scope at a time. A transport retry
keeps its ID and complete payload even if another local edit follows. Only a
confirmed acknowledgement advances a queued follow-up's expected version.

## Conflict recovery

An allocation conflict preserves the entire local intent for review. It blocks
later budget commands, including changes already queued before the conflict.
Unrelated content remains independently synchronized. Remote shared budget data
is cached separately from the local pending vector, including across relaunch.

Account lists the affected event under **Budget changes need review**. **Use
shared budget** opens a native alert with explicit Cancel and destructive actions,
then discards the complete unsynced budget
intent and restores the latest cached shared vector. Other local edits and
their outbox records are kept. An unresolved in-flight request cannot be
discarded until its idempotent server result is known. If the shared vector is
not available yet, synchronize first. The user can then make a fresh allocation
against the shared balances; there is no automatic last-write-wins override.

Creating a child event and allocating its budget are still separate remote
content and budget operations. A remote conflict can leave an unfunded child
while its allocation intent needs review. The full allocation is atomic; this
does not claim the entire remote Schedule workflow is a single transaction.

## Verification and rollout limits

The web/server Decimal.js work is owned by a separate agent, coordinated through
its existing Codex chat. iOS continues using Foundation Decimal. Archive and
expense projections must send numeric JSON major units and native enum values
such as `foodAndDrink`; budget commands send integer cents and explicit nulls.
Database decimal strings must not be copied into native money fields. Inbound
codec, bootstrap and pull regressions cover that contract without adding a
JavaScript dependency to the app.

See [testing verification](testing-verification.md) for final executed test
counts and artifacts. Native tests cover paid history, authorization, funding,
command staging, retries, conflict blocking and recovery. Isolated PostgreSQL
tests cover competing managers, atomic rejection, idempotence and legacy-write
protection. Native UI tests cover ordinary budget navigation and Account review.

Raw archive merging remains a compatibility primitive, not the budget acceptance
boundary. The legacy independent-field counterexample is retained as a
characterization; safe collaboration depends on the server command and client
capability contract. Existing malformed budget data is not repaired by this
change. No shared database reset or real account budget mutation is required by
the test fixtures.

Server and native changes must be released together through an authorized
rollout. Physical-device networking/relaunch acceptance and historical-data
inspection remain separate release checks. No payment provider, reimbursement,
multi-currency conversion or spending-approval workflow is introduced here.
