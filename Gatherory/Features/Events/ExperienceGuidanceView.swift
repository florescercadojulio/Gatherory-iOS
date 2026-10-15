import SwiftUI

extension PlanningWorkspace {
    /// Invitation surfaces deliberately never show private planning guidance,
    /// even when their viewer also happens to be an event manager.
    func visibleGuides(for reference: EventReference, invitation: Bool = false) -> [ExperienceGuide] {
        let eventID: UUID
        switch reference {
        case .main:
            guard !isMainEventDeleted else { return [] }
            eventID = mainEventID
        case .subevent(let id):
            guard !isScopedEvent, timeline.contains(where: { $0.id == id }) else { return [] }
            eventID = id
        case .idea: return []
        }
        let viewer = currentViewerMember(for: reference)
        guard viewer != nil || isInvitationProjection else { return [] }
        let isPlanner = !isInvitationProjection && (viewer.map { $0.participantRole != .guest } ?? false)
        return guides.filter {
            $0.eventID == eventID && ($0.visibility == .eventParticipants || (!invitation && isPlanner))
        }.sorted {
            $0.sortOrder == $1.sortOrder ? $0.id.uuidString < $1.id.uuidString : $0.sortOrder < $1.sortOrder
        }
    }
}

struct ExperienceGuidanceView: View {
    @Environment(PlanningWorkspace.self) private var workspace
    let reference: EventReference

    var body: some View {
        List(workspace.visibleGuides(for: reference)) { guide in
            Section {
                Text(guide.body)
                    .textSelection(.enabled)
            } header: {
                Text(guide.title)
            } footer: {
                if guide.visibility == .planningOnly {
                    Text("Planning team only")
                } else {
                    Text("Shared with event guests")
                }
            }
        }
        .navigationTitle("Planning Guide")
        .navigationBarTitleDisplayMode(.inline)
    }
}
