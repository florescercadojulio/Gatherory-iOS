import SwiftUI

/// Personal preferences remain visible at the explicit scheduling decision.
struct IdeaScheduleTeamInput: View {
    let summary: TeamResponseSummary
    var accessibilityIdentifier = "idea.schedule.teamInput"

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            if summary.responded > 0 {
                Text(String(localized: "idea.schedule.teamInput.votes",
                            defaultValue: "\(summary.love) love it · \(summary.maybe) maybe · \(summary.pass) pass"))
            }
            if summary.unanswered > 0 {
                Text(String(localized: "idea.schedule.teamInput.unanswered",
                            defaultValue: "\(summary.unanswered) unanswered"))
            } else if summary.total == 0 {
                Text("No team responses yet")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
