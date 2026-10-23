## Native iOS UI

Use SwiftUI system controls and the existing Gatherory iOS design system.
Do not apply ReUI, shadcn/ui, React or Tailwind guidance to this native app.
Do not install web UI packages for native UI work.

Prefer existing native flows as references: onboarding's `NewWorkspaceView`
and the shared `EventDateTimeEditorView` demonstrate the app's event-creation
patterns. Keep unrelated screens unchanged when reusing their patterns.
Use native toolbar placements, forms and presentation APIs before introducing
custom containers or gesture handling. Verify standard Light/Dark layouts;
do not add dedicated super-large layout tests unless the task requests them.

## Feature regression coverage

Add or update focused regression tests alongside feature and behavior changes.
Cover user-visible outcomes and affected state/recovery boundaries; use native
UI tests for gestures or navigation that unit tests cannot prove. Run relevant
checks and record actual results and remaining acceptance limits in the docs.
