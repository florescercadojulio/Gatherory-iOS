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

/// Guest attendance stays independent of planning role and collaborator approval.
struct ManageGuestsCard: View {
    let summary: ManageEventSummary

    var body: some View {
        NavigationLink {
            EventPeopleView(reference: summary.reference, section: .guests)
        } label: {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
                HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.compact) {
                    Text("Guests")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Text(summary.attendance.total.formatted())
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .accessibilityHidden(true)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                }
                RSVPOverviewBar(summary: summary.attendance)
            }
            .foregroundStyle(AppTheme.ColorToken.textPrimary)
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(AppTheme.ColorToken.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// Collaborator navigation and the existing transient join-request review.
struct ManageCollaboratorsCard: View {
    @Environment(PlanningWorkspace.self) private var workspace
    @Environment(AuthenticationSession.self) private var authentication
    @Environment(WorkspaceCloudSyncController.self) private var cloudSync
    let summary: ManageEventSummary
    let approval: ManageMetric
    @ScaledMetric(relativeTo: .largeTitle) private var countSize = 48

    private var latestRequest: EventJoinRequest? {
        ManageCollaboratorReview.latestRequest(in: workspace, store: workspace.joinRequestStore, reference: summary.reference,
                                              accountID: authentication.currentUser?.id)
    }

    private var isCaughtUp: Bool {
        ManageCollaboratorReview.isCaughtUp(in: workspace, store: workspace.joinRequestStore,
            reference: summary.reference, accountID: authentication.currentUser?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            NavigationLink {
                EventPeopleView(reference: summary.reference, section: .collaborators)
            } label: {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                    heading
                    VStack(alignment: .leading, spacing: 2) {
                        Text(approval.value)
                            .font(.system(size: countSize, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.ColorToken.accent)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                        Text(approval.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2, reservesSpace: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(approval.label)
                    .accessibilityValue(approval.value)
                }
                .foregroundStyle(AppTheme.ColorToken.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityElement(children: .combine)

            // Status changes must not resize the dashboard or move the review actions.
            let error = summary.canManageInvitations
                ? workspace.joinRequestStore.error(eventID: summary.eventID, accountID: authentication.currentUser?.id) : nil
            Text(error ?? " ").font(.footnote).foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
                .accessibilityHidden(error == nil)
            Spacer(minLength: 16)
            Divider()
                .padding(.bottom, 4)
            Text(latestRequest?.name ?? (isCaughtUp ? String(localized: "All caught up") : " "))
                .font(.subheadline)
                .foregroundStyle(latestRequest == nil ? .secondary : .primary)
                .lineLimit(2, reservesSpace: true)
                .accessibilityHidden(latestRequest == nil && !isCaughtUp)
            HStack(alignment: .bottom, spacing: 0) {
                reviewButtons(latestRequest)
                Spacer(minLength: 0)
                NavigationLink {
                    EventPeopleView(reference: summary.reference, section: .collaborators)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Collaborators")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.ColorToken.textPrimary)
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.ColorToken.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func reviewButtons(_ request: EventJoinRequest?) -> some View {
        ZStack {
            HStack(spacing: AppTheme.Spacing.compact) {
                Button(role: .destructive) { if let request { review(request, action: .decline) } } label: {
                    Image(systemName: "xmark.circle").font(.title2)
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityLabel(String(format: String(localized: "Decline %@"), request?.name ?? ""))
                Button { if let request { review(request, action: .approve) } } label: {
                    Image(systemName: "checkmark.circle.fill").font(.title2)
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityLabel(String(format: String(localized: "Approve %@"), request?.name ?? ""))
            }
            .buttonStyle(.borderless)
            .disabled(request == nil || workspace.joinRequestStore.reviewingRequestID != nil)
            .opacity(request == nil || isReviewing(request) ? 0 : 1)
            .accessibilityHidden(request == nil || isReviewing(request))
            if isReviewing(request) {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func isReviewing(_ request: EventJoinRequest?) -> Bool {
        guard let request else { return false }
        return workspace.joinRequestStore.reviewingRequestID == request.id
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

    private var heading: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.compact) {
            Text("Collaborators")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
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
