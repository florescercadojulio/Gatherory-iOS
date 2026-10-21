import SwiftUI
import UIKit

struct EventScheduleShareButton: View {
    let action: () -> Void

    var body: some View {
        Button("Share Event Schedule", systemImage: "square.and.arrow.up", action: action)
            .accessibilityHint("Share a copy of this event’s dates, times, and locations")
            .accessibilityIdentifier("event-share-schedule")
    }
}

struct EventCSVSharePayload {
    let data: Data
    let kind: EventCSVExportKind
}

/// A pending export retains its exact scope, never a cached roster or file.
struct EventCSVExportRequest: Identifiable {
    let id = UUID()
    let reference: EventReference
    let workspaceID: UUID
    let accountID: String
    let principalGeneration: UInt64
    let kind: EventCSVExportKind

    @MainActor
    static func accountID(authentication: AuthenticationSession?) -> String? {
        guard let authentication, !authentication.isSigningOut,
              case .account(let id) = authentication.notificationPrincipal else { return nil }
        return id
    }

    @MainActor
    static func canExport(
        kind: EventCSVExportKind, workspace: PlanningWorkspace,
        reference: EventReference, authentication: AuthenticationSession?
    ) -> Bool {
        let accountID = accountID(authentication: authentication)
        switch kind {
        case .schedule:
            return EventScheduleShare.canShare(workspace: workspace, reference: reference, accountID: accountID)
        case .guestList:
            return EventGuestListExport.canExport(workspace: workspace, reference: reference, accountID: accountID)
        }
    }

    @MainActor
    static func make(
        kind: EventCSVExportKind, workspace: PlanningWorkspace,
        reference: EventReference, authentication: AuthenticationSession?
    ) -> Self? {
        guard let authentication, let accountID = accountID(authentication: authentication),
              canExport(kind: kind, workspace: workspace, reference: reference, authentication: authentication) else { return nil }
        return Self(reference: reference, workspaceID: workspace.mainEventID,
                    accountID: accountID, principalGeneration: authentication.principalGeneration, kind: kind)
    }

    @MainActor
    func isAuthorized(workspace: PlanningWorkspace, authentication: AuthenticationSession?) -> Bool {
        workspaceID == workspace.mainEventID &&
        accountID == Self.accountID(authentication: authentication) &&
        principalGeneration == authentication?.principalGeneration &&
        Self.canExport(kind: kind, workspace: workspace, reference: reference, authentication: authentication)
    }

    @MainActor
    func makePayload(workspace: PlanningWorkspace, authentication: AuthenticationSession?) -> EventCSVSharePayload? {
        guard isAuthorized(workspace: workspace, authentication: authentication) else { return nil }
        switch kind {
        case .schedule:
            guard let snapshot = EventScheduleShare.makeSnapshot(workspace: workspace, reference: reference, accountID: accountID) else { return nil }
            return EventCSVSharePayload(data: snapshot.data, kind: .schedule)
        case .guestList:
            guard let snapshot = EventGuestListExport.makeSnapshot(workspace: workspace, reference: reference, accountID: accountID) else { return nil }
            return EventCSVSharePayload(data: snapshot.data, kind: .guestList)
        }
    }
}

/// Attach at the screen root so menu dismissal cannot remove the presenter.
struct EventCSVExportPresentation: ViewModifier {
    @Environment(PlanningWorkspace.self) private var workspace
    @Environment(AuthenticationSession.self) private var authentication: AuthenticationSession?
    @Binding var request: EventCSVExportRequest?
    @State private var didFail = false
    @State private var failureKind: EventCSVExportKind = .schedule

    private var failureTitle: LocalizedStringKey {
        switch failureKind {
        case .schedule: "Couldn’t Share Schedule"
        case .guestList: "Couldn’t Export Guest List"
        }
    }

    private var failureMessage: LocalizedStringKey {
        switch failureKind {
        case .schedule: "The schedule file couldn’t be created. Please try again."
        case .guestList: "The guest list file couldn’t be created. Please try again."
        }
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: $request) { exportRequest in
                EventCSVShareSheet {
                    exportRequest.makePayload(workspace: workspace, authentication: authentication)
                } onDismiss: {
                    if request?.id == exportRequest.id { request = nil }
                } onFailure: {
                    guard request?.id == exportRequest.id else { return }
                    request = nil
                    failureKind = exportRequest.kind
                    didFail = true
                }
                .ignoresSafeArea()
            }
            .alert(failureTitle, isPresented: $didFail) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(failureMessage)
            }
            .onChange(of: request.map { $0.isAuthorized(workspace: workspace, authentication: authentication) }) { _, authorized in
                if authorized == false { request = nil }
            }
            .onChange(of: request?.makePayload(workspace: workspace, authentication: authentication)?.data) { oldData, newData in
                // A system sheet holds a frozen copy. Dismiss it if the current
                // allowed roster, RSVP statuses, or schedule contents change.
                if oldData != nil, oldData != newData { request = nil }
            }
    }
}

struct EventCSVShareSheet: UIViewControllerRepresentable {
    let makePayload: @MainActor () -> EventCSVSharePayload?
    let onDismiss: @MainActor () -> Void
    let onFailure: @MainActor () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        // Revalidate after the menu closes and immediately before presentation;
        // a permission or account change must never expose a previous payload.
        guard let payload = makePayload() else {
            Task { @MainActor in onDismiss() }
            return UIActivityViewController(activityItems: [], applicationActivities: nil)
        }
        let attachment: EventScheduleShareAttachment
        do {
            attachment = try EventScheduleShareAttachment(data: payload.data, kind: payload.kind)
            context.coordinator.attachment = attachment
        } catch {
            Task { @MainActor in onFailure() }
            return UIActivityViewController(activityItems: [], applicationActivities: nil)
        }
        let controller = UIActivityViewController(activityItems: [attachment.url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            Task { @MainActor in
                context.coordinator.cleanup()
                onDismiss()
            }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }

    static func dismantleUIViewController(_ controller: UIActivityViewController, coordinator: Coordinator) {
        coordinator.cleanup()
    }

    @MainActor final class Coordinator {
        var attachment: EventScheduleShareAttachment?

        func cleanup() {
            attachment?.cleanup()
            attachment = nil
        }
    }
}
