#if DEBUG
import Foundation

/// Local, ephemeral reproduction of a long conference idea; never synced.
enum DecisionCardUITestFixtures {
    static func applying(to workspaces: [PlanningWorkspace]) -> [PlanningWorkspace] {
        guard ProcessInfo.processInfo.arguments.contains("-LongDecisionCardUITest"),
              AppRuntimeConfiguration.usesEphemeralDataStore,
              AppRuntimeConfiguration.seedsDevelopmentData,
              AppRuntimeConfiguration.skipsAuthentication,
              let original = workspaces.first else { return workspaces }
        var archive = WorkspaceArchiveV1(workspace: original)
        archive.title = "IBM TechXchange 2026 — Personal & Humphrey Plan"
        archive.ideaResponses = []
        archive.ideas = [
            PlanningIdea(
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
                title: "Conference outcomes: bounded modernization, backup, and platform decisions",
                note: "Bring back three decisions: one small on-premises IBM i modernization pilot with test baseline/validation/rollback; compare backup approaches against acceptable pause, RTO and RPO; assess Power11/cloud dev-test or DR value and recurring cost. Humphrey business-continuity focus is a planning inference, not a claim about its ERP or application architecture.",
                category: .other,
                submittedBy: "Gatherory App Review"
            )
        ]
        return [archive.makeWorkspace()] + Array(workspaces.dropFirst())
    }
}
#endif
