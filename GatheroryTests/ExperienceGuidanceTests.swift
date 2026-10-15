import Foundation
import Testing
@testable import Gatherory

@MainActor
struct ExperienceGuidanceTests {
    @Test("Invitations exclude planner guidance even for the host")
    func audiencesRemainSeparate() {
        let workspace = PlanningWorkspace.newWorkspace(title: "Wedding", startsAt: .now, eventLocation: nil, imageData: nil)
        workspace.guides = [guide(eventID: workspace.mainEventID, visibility: .planningOnly), guide(eventID: workspace.mainEventID, visibility: .eventParticipants)]
        #expect(workspace.visibleGuides(for: .main).count == 2)
        #expect(workspace.visibleGuides(for: .main, invitation: true).map(\.visibility) == [.eventParticipants])
        workspace.isInvitationProjection = true
        #expect(workspace.visibleGuides(for: .main).map(\.visibility) == [.eventParticipants])
    }

    @Test("A child projection cannot show guidance for a parent or sibling reference")
    func scopeIsolation() {
        let workspace = PlanningWorkspace.newWorkspace(title: "Reception", startsAt: .now, eventLocation: nil, imageData: nil)
        workspace.isScopedEvent = true
        let siblingID = UUID()
        workspace.guides = [guide(eventID: siblingID, visibility: .eventParticipants)]
        #expect(workspace.visibleGuides(for: .main).isEmpty)
        #expect(workspace.visibleGuides(for: .subevent(siblingID)).isEmpty)
        #expect(workspace.visibleGuides(for: .idea(siblingID)).isEmpty)
    }

    private func guide(eventID: UUID, visibility: ExperienceGuideVisibility) -> ExperienceGuide {
        ExperienceGuide(id: UUID(), eventID: eventID, key: "guide", title: "Guide", body: "Content", sortOrder: 0, visibility: visibility)
    }
}
