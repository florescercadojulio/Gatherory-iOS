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
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.compact) {
                    Text("Guests")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                }
                RSVPOverviewRing(summary: summary.attendance)
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

/// Collaborator count stays separate from the inline join-request actions.
struct ManageCollaboratorsCard: View {
    let summary: ManageEventSummary
    let approval: ManageMetric
    @ScaledMetric(relativeTo: .largeTitle) private var countSize = 48

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            NavigationLink {
                EventPeopleView(reference: summary.reference, section: .collaborators)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Collaborators")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(AppTheme.ColorToken.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .center, spacing: 1) {
                Text(approval.value)
                    .font(.system(size: countSize * 0.9, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ColorToken.accent)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(approval.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(approval.label)
            .accessibilityValue(approval.value)
        }
        .foregroundStyle(AppTheme.ColorToken.textPrimary)
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.ColorToken.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

/// A separate tile for reviewing the latest collaborator join request.
struct ManageQuickApprovalCard: View {
    @Environment(PlanningWorkspace.self) private var workspace
    @Environment(AuthenticationSession.self) private var authentication
    @Environment(WorkspaceCloudSyncController.self) private var cloudSync
    let summary: ManageEventSummary

    private var requests: [EventJoinRequest] {
        guard summary.canManageInvitations else { return [] }
        return workspace.joinRequestStore.requests(eventID: summary.eventID, accountID: authentication.currentUser?.id)
    }

    private var isCaughtUp: Bool {
        ManageCollaboratorReview.isCaughtUp(in: workspace, store: workspace.joinRequestStore,
            reference: summary.reference, accountID: authentication.currentUser?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Quick approval")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ColorToken.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)

            if let error = summary.canManageInvitations
                ? workspace.joinRequestStore.error(eventID: summary.eventID, accountID: authentication.currentUser?.id)
                : nil {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.top, 8)
            } else {
                Spacer(minLength: 8)
                if requests.isEmpty {
                    emptyRequestsState
                } else {
                    pendingRequestRow(requests[requests.count - 1])
                }
                Spacer(minLength: 8)
            }
        }
        .foregroundStyle(AppTheme.ColorToken.textPrimary)
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.ColorToken.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    @ViewBuilder
    private var emptyRequestsState: some View {
        if isCaughtUp {
            Label(String(localized: "All caught up"), systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .center)
        } else if workspace.joinRequestStore.isLoading(eventID: summary.eventID) {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 64)
        } else if !summary.canManageInvitations {
            Text(String(localized: "Manager only"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .center)
        } else {
            Text(String(localized: "No pending requests"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .center)
        }
    }

    private func knownMember(for request: EventJoinRequest) -> WorkspaceMember? {
        workspace.members.first {
            $0.email?.localizedCaseInsensitiveCompare(request.email) == .orderedSame
        }
    }

    private func pendingRequestRow(_ request: EventJoinRequest) -> some View {
        VStack(spacing: 7) {
            Group {
                if let member = knownMember(for: request) {
                    ParticipantAvatarView(member: member, size: 56, style: .accent)
                } else {
                    Text(initials(for: request.name))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.ColorToken.accent)
                        .frame(width: 56, height: 56)
                        .background(AppTheme.ColorToken.accent.opacity(0.14), in: Circle())
                        .overlay(Circle().stroke(.primary.opacity(0.1), lineWidth: 1))
                }
            }
            .accessibilityHidden(true)

            Text(request.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(request.name)

            HStack(spacing: 12) {
                if isReviewing(request) {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    Button(role: .destructive) { review(request, action: .decline) } label: {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 27, weight: .medium))
                            .foregroundStyle(AppTheme.ColorToken.destructive)
                            .frame(width: 48, height: 48)
                            .background(AppTheme.ColorToken.destructive.opacity(0.1), in: Circle())
                    }
                    .accessibilityLabel(String(format: String(localized: "Decline %@"), request.name))

                    Button { review(request, action: .approve) } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 27, weight: .medium))
                            .foregroundStyle(AppTheme.ColorToken.accent)
                            .frame(width: 48, height: 48)
                            .background(AppTheme.ColorToken.accent.opacity(0.14), in: Circle())
                    }
                    .accessibilityLabel(String(format: String(localized: "Approve %@"), request.name))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func initials(for name: String) -> String {
        let parts = name.split(whereSeparator: \.isWhitespace)
        return String(parts.prefix(2).compactMap(\.first)).uppercased()
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

}

private struct RSVPOverviewRing: View {
    let summary: ManageAttendanceSummary

    private var segments: [(count: Int, color: Color, label: String)] {
        [
            (summary.going, .green, String(localized: "Going")),
            (summary.maybe, .yellow, String(localized: "Maybe")),
            (summary.declined, .red, String(localized: "Can't go")),
            (summary.awaiting, .gray, String(localized: "Awaiting"))
        ]
    }

    private var visibleSegments: [(count: Int, color: Color, start: CGFloat, end: CGFloat)] {
        guard summary.total > 0 else { return [] }
        var current = 0.0
        return segments.compactMap { segment in
            guard segment.count > 0 else { return nil }
            let start = current
            current += Double(segment.count) / Double(summary.total)
            return (segment.count, segment.color, CGFloat(start), CGFloat(current))
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(AppTheme.ColorToken.textSecondary.opacity(0.18), style: StrokeStyle(lineWidth: 9, lineCap: .butt))
                ForEach(visibleSegments.indices, id: \.self) { index in
                    let segment = visibleSegments[index]
                    Circle()
                        .trim(from: segment.start, to: segment.end)
                        .stroke(segment.color, style: StrokeStyle(lineWidth: 9, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 0) {
                    Text(summary.total.formatted())
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .monospacedDigit()
                    Text("Guests")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 88, height: 88)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    legendItem(segments[0])
                    legendItem(segments[1])
                }
                HStack(spacing: 8) {
                    legendItem(segments[2])
                    legendItem(segments[3])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Guest List")
        .accessibilityValue(segments.map { "\($0.count.formatted()) \($0.label)" }.joined(separator: ", "))
    }

    private func legendItem(_ segment: (count: Int, color: Color, label: String)) -> some View {
        HStack(spacing: 4) {
            Circle().fill(segment.color).frame(width: 6, height: 6)
            Text("\(segment.count.formatted()) \(segment.label)")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
