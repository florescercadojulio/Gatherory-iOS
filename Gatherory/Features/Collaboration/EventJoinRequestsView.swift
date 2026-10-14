import SwiftUI

/// A persistent entry point, including when there are no cached requests yet.
struct EventJoinRequestsLink: View {
    @Environment(PlanningWorkspace.self) private var workspace
    @Environment(AuthenticationSession.self) private var authentication
    @Environment(\.scenePhase) private var scenePhase
    let eventID: UUID

    private var count: Int {
        workspace.joinRequestStore.requests(eventID: eventID, accountID: authentication.currentUser?.id).count
    }

    var body: some View {
        NavigationLink {
            EventJoinRequestsView(eventID: eventID)
        } label: {
            HStack(spacing: AppTheme.Spacing.standard) {
                Label("Join Requests", systemImage: "person.crop.circle.badge.clock")
                    .font(.headline)
                Spacer(minLength: AppTheme.Spacing.compact)
                Text(count.formatted()).monospacedDigit()
                Image(systemName: "chevron.right").accessibilityHidden(true)
            }
            .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("event-join-requests")
        .task(id: "\(eventID)|\(authentication.currentUser?.id ?? "")|\(scenePhase)") {
            guard scenePhase == .active, let accountID = authentication.currentUser?.id else { return }
            await workspace.joinRequestStore.refresh(eventID: eventID, accountID: accountID)
        }
    }
}

struct EventJoinRequestsView: View {
    @Environment(PlanningWorkspace.self) private var workspace
    @Environment(AuthenticationSession.self) private var authentication
    @Environment(WorkspaceCloudSyncController.self) private var cloudSync
    let eventID: UUID

    private var reference: EventReference { eventID == workspace.mainEventID ? .main : .subevent(eventID) }
    private var canReview: Bool { workspace.canManageInvitations(for: reference) }
    private var store: EventJoinRequestStore { workspace.joinRequestStore }
    private var requests: [EventJoinRequest] { store.requests(eventID: eventID, accountID: authentication.currentUser?.id) }

    var body: some View {
        List {
            if canReview {
                if let error = store.error(eventID: eventID, accountID: authentication.currentUser?.id) {
                    Section {
                        Text(error).foregroundStyle(.secondary)
                        Button("Try Again") { Task { await refresh() } }
                    }
                }
                if requests.isEmpty {
                    if store.isLoading(eventID: eventID) {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if store.error(eventID: eventID, accountID: authentication.currentUser?.id) == nil {
                        ContentUnavailableView("No Join Requests", systemImage: "person.crop.circle.badge.checkmark",
                            description: Text("People waiting for approval will appear here."))
                    }
                } else {
                    ForEach(requests) { request in
                        EventJoinRequestRow(request: request, isReviewing: store.reviewingRequestID == request.id,
                                            isDisabled: store.reviewingRequestID != nil) { action in
                            Task {
                                guard canReview, let accountID = authentication.currentUser?.id else { return }
                                if await store.review(request, eventID: eventID, accountID: accountID, action: action) {
                                    await cloudSync.refreshCollaboration()
                                }
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("Join Requests", systemImage: "lock")
            }
        }
        .navigationTitle("Join Requests")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await refresh() }
        .task(id: "\(eventID)|\(authentication.currentUser?.id ?? "")") { await refresh() }
    }

    private func refresh() async {
        guard canReview, let accountID = authentication.currentUser?.id else { return }
        await store.refresh(eventID: eventID, accountID: accountID, force: true)
    }
}

struct EventJoinRequestRow: View {
    let request: EventJoinRequest
    let isReviewing: Bool
    let isDisabled: Bool
    let review: (JoinRequestReviewAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Text(request.name).font(.headline)
            Text(request.email).font(.subheadline).foregroundStyle(.secondary)
            Text(LocalizedStringKey(request.permission.title)).font(.footnote).foregroundStyle(.secondary)
            HStack {
                Button("Decline", role: .destructive) { review(.decline) }.buttonStyle(.borderless)
                Spacer()
                if isReviewing { ProgressView() }
                Button("Approve") { review(.approve) }.buttonStyle(.borderedProminent)
            }
            .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
            .disabled(isDisabled)
        }
        .padding(.vertical, AppTheme.Spacing.compact)
    }
}

struct JoinRequestCountBadge: View {
    let count: Int

    var body: some View {
        Text(count.formatted())
            .font(.caption2.bold())
            .monospacedDigit()
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .foregroundStyle(.white)
            .background(.red, in: Capsule())
            .accessibilityHidden(true)
    }
}
