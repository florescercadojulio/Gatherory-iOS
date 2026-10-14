import SwiftUI

/// Attendance is independent of planning role and collaborator approval.
struct ManageAttendanceSummary {
    let going: Int
    let maybe: Int
    let declined: Int
    let awaiting: Int
    var total: Int { going + maybe + declined + awaiting }

    init(participants: [WorkspaceMember]) {
        going = participants.filter { $0.attendance == .going }.count
        maybe = participants.filter { $0.attendance == .maybe }.count
        declined = participants.filter { $0.attendance == .declined }.count
        awaiting = participants.filter { $0.attendance == .invited }.count
    }
}

/// Two distinct actions share one surface, without making the bar interactive.
struct ManagePeoplePill: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(PlanningWorkspace.self) private var workspace
    @Environment(AuthenticationSession.self) private var authentication
    @Environment(WorkspaceCloudSyncController.self) private var cloudSync
    let summary: ManageEventSummary
    let approval: ManageMetric

    private var latestRequest: EventJoinRequest? {
        ManageCollaboratorReview.latestRequest(in: workspace, store: workspace.joinRequestStore, reference: summary.reference,
                                              accountID: authentication.currentUser?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            NavigationLink {
                EventPeopleView(reference: summary.reference, section: .guests)
            } label: {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
                    heading("Guests", symbol: "person.3.fill")
                    RSVPOverviewBar(summary: summary.attendance)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityElement(children: .combine)
            Divider().accessibilityHidden(true)
            NavigationLink {
                EventPeopleView(reference: summary.reference, section: .collaborators)
            } label: {
                heading("Collaborators", symbol: "person.crop.circle.badge.clock", count: approval.value)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue("\(approval.value) \(approval.label)")

            if let request = latestRequest {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                        Text(request.name).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        reviewButtons(request)
                    }
                } else {
                    HStack(spacing: AppTheme.Spacing.compact) {
                        Text(request.name).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        reviewButtons(request)
                    }
                }
            }
            if summary.canManageInvitations,
               let error = workspace.joinRequestStore.error(eventID: summary.eventID, accountID: authentication.currentUser?.id) {
                Text(error).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.ColorToken.textPrimary)
        .padding(.horizontal, 28)
        .padding(.vertical, AppTheme.Spacing.spacious)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.ColorToken.surface, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
    }

    private func reviewButtons(_ request: EventJoinRequest) -> some View {
        HStack(spacing: AppTheme.Spacing.compact) {
            if workspace.joinRequestStore.reviewingRequestID == request.id { ProgressView() }
            Button(role: .destructive) { review(request, action: .decline) } label: {
                Image(systemName: "xmark.circle").font(.title2)
                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(String(format: String(localized: "Decline %@"), request.name))
            Button { review(request, action: .approve) } label: {
                Image(systemName: "checkmark.circle.fill").font(.title2)
                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(String(format: String(localized: "Approve %@"), request.name))
        }
        .buttonStyle(.borderless)
        .disabled(workspace.joinRequestStore.reviewingRequestID != nil)
    }

    private func review(_ request: EventJoinRequest, action: JoinRequestReviewAction) {
        guard let accountID = authentication.currentUser?.id else { return }
        let reference = summary.reference
        Task {
            guard authentication.currentUser?.id == accountID else { return }
            let reviewed = await ManageCollaboratorReview.review(request, in: workspace, store: workspace.joinRequestStore, reference: reference,
                                                                accountID: accountID, action: action)
            guard reviewed, authentication.currentUser?.id == accountID else { return }
            await cloudSync.refreshCollaboration()
        }
    }

    private func heading(_ title: LocalizedStringKey, symbol: String, count: String? = nil) -> some View {
        HStack {
            Label(title, systemImage: symbol).font(.headline)
            Spacer(minLength: 8)
            if let count {
                Text(count).font(.subheadline.weight(.semibold)).monospacedDigit().accessibilityHidden(true)
            }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).accessibilityHidden(true)
        }
    }
}

private struct RSVPOverviewBar: View {
    let summary: ManageAttendanceSummary

    private var segments: [(count: Int, color: Color, symbol: String, label: String)] {
        [
            (summary.going, .green, "checkmark", String(localized: "Going")),
            (summary.maybe, .yellow, "questionmark", String(localized: "Maybe")),
            (summary.declined, .red, "xmark", String(localized: "Can't go")),
            (summary.awaiting, .gray, "ellipsis", String(localized: "Awaiting RSVP"))
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                let visible = segments.filter { $0.count > 0 }
                let available = max(0, proxy.size.width - CGFloat(max(0, visible.count - 1)) * 2)
                HStack(spacing: 2) {
                    ForEach(visible.indices, id: \.self) { index in
                        let segment = visible[index]
                        let width = available * CGFloat(segment.count) / CGFloat(max(1, summary.total))
                        Rectangle().fill(segment.color)
                            .overlay {
                                if width >= 20 {
                                    Image(systemName: segment.symbol)
                                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.black)
                                }
                            }
                            .frame(width: width)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.3))
                .clipShape(Capsule())
                .overlay { Capsule().stroke(.primary.opacity(0.3), lineWidth: 0.5) }
            }
            .frame(height: 18)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Guest List")
        .accessibilityValue(segments.map { "\($0.count.formatted()) \($0.label)" }.joined(separator: ", "))
    }
}
