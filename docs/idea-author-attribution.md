# Idea author photos

November 2, 2026. Implemented in native source; no deployment or TestFlight upload.

Ideas detail and Decide cards share `IdeaSubmitterAttribution`. Their author row
uses a fixed 26-point circular photo beside the existing submitter name. Shared
by and Proposed By metadata use the same photo while retaining their labels.
The image is decorative for accessibility; the existing Suggested by name is
still announced. No new action or navigation is added to the attribution.

The resolver matches the idea's `submittedByUserID` to the current account ID
first, then to a member's linked `userID` in the current workspace. It uses the
current account photo or the member's existing local asset/remote profile URL.
It does not guess identity from names, initials or email. Ideas without a known
linked author retain a person icon. Known people without an available photo use
initials, including remote image loading/failure. Fixed image bounds keep the
row's geometry stable while photos load.

Workspace participant sync already carries `profileImageURL`; this change adds
no profile endpoint, server contract, database migration or account lookup.
Public Blueprint previews remain separate from private workspace attribution.

## Verification

Seven focused identity tests passed: current account, collaborator asset/URL,
unrelated viewer isolation, legacy IDs/duplicate names, removed authors,
account changes and known authors without photos. One native UI method passed
in **59.492 seconds**, opening the Riley-authored birthday idea from both Ideas
and Decide in **Light and Dark**, verifying Suggested by Riley Kim and the
existing Edit idea action. It changes no votes and takes no screenshots.

Result: `/tmp/gatherory-author-avatars-20261102.xcresult`; matching log:
`/tmp/gatherory-author-avatars-20261102.log`. English/Spanish localization coverage
passes for 1,800 strings, with the existing nonliteral extraction advisory;
`git diff --check` passes.

The native journey uses bundled fixture portraits. Identity tests cover remote
URL selection, but this run does not exercise a live provider photo download or
compare photo pixels. Existing AsyncImage fallback handles loading/failure.
