import Foundation

/// Builds the Movie Night lesson from the checked-in, revisioned blueprint
/// contract. This factory is deliberately local and never creates a catalog
/// installation receipt or synthetic collaborators.
struct BundledMovieNightTour {
    struct Workspace {
        let planningWorkspace: PlanningWorkspace
        let snackIdeaID: UUID
        let eventIdeaID: UUID
    }

    enum FactoryError: Error {
        case missingBundledBlueprint
        case invalidBlueprint
    }

    static func makeWorkspace(
        account: UserAccount,
        localJSON: Data,
        today: Date = .now,
        timeZoneIdentifier: String = TimeZone.autoupdatingCurrent.identifier
    ) throws -> Workspace {
        let entry: BlueprintCatalogEntry
        do {
            entry = try JSONDecoder().decode(BlueprintCatalogEntry.self, from: localJSON)
        } catch {
            throw FactoryError.invalidBlueprint
        }
        guard entry.catalogKey == "movie_night", entry.revision == 1,
              entry.definition.blueprint.id == "movie_night",
              entry.definition.blueprint.revision == 1 else {
            throw FactoryError.invalidBlueprint
        }
        let customization = BlueprintCustomization()
        let content: (tree: BlueprintExperienceTreeConfig, ideas: BlueprintIdeasConfig)
        do {
            content = try customization.applying(to: entry)
        } catch {
            throw FactoryError.invalidBlueprint
        }

        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .autoupdatingCurrent
        let workspace = PlanningWorkspace.newWorkspace(
            title: entry.definition.blueprint.name,
            startsAt: today,
            timeZoneIdentifier: timeZoneIdentifier,
            eventLocation: nil,
            imageData: nil,
            owner: account
        )
        let rootID = workspace.mainEventID
        let hostID = workspace.members[0].id
        for child in content.tree.children {
            var proposedDate = today
            if let proposal = child.scheduleProposal {
                proposedDate = calendar.date(byAdding: .day, value: proposal.dayOffset, to: today) ?? today
                let components = proposal.localTime.split(separator: ":").compactMap { Int($0) }
                if components.count == 2 {
                    proposedDate = calendar.date(bySettingHour: components[0], minute: components[1], second: 0, of: proposedDate) ?? proposedDate
                }
            }
            workspace.addTimelineItem(TimelineItem(
                title: child.title,
                category: TimelineCategory(rawValue: child.category) ?? .other,
                purpose: child.purpose == "part_of_event" ? .eventExperience : .planning,
                scheduledAt: proposedDate,
                schedulingState: .scheduled,
                location: "",
                timeZoneIdentifier: timeZoneIdentifier,
                participantIDs: [hostID],
                parentEventID: rootID,
                status: .approved
            ))
        }
        var ideaIDsByBlueprintKey: [String: UUID] = [:]
        for definition in content.ideas.ideas {
            let configuration: IdeaConfiguration? = if definition.category == "event" {
                .event(EventIdeaConfiguration(
                    category: .other,
                    purpose: .eventExperience,
                    proposedDate: nil,
                    location: nil
                ))
            } else {
                nil
            }
            let idea = PlanningIdea(
                eventID: rootID,
                title: definition.title,
                note: definition.notes ?? "",
                category: IdeaCategory(rawValue: definition.category) ?? .other,
                submittedBy: account.displayName,
                submittedByUserID: account.id,
                configuration: configuration
            )
            ideaIDsByBlueprintKey[definition.key] = idea.id
            workspace.addIdea(idea)
        }
        guard let snackIdea = content.ideas.ideas.first(where: {
                  $0.key == "popcorn_bar" && $0.category == IdeaCategory.food.rawValue && $0.target == .main
              }),
              let eventIdea = content.ideas.ideas.first(where: {
                  $0.key == "watch_movie" && $0.category == IdeaCategory.event.rawValue && $0.target == .main
              }),
              let snackIdeaID = ideaIDsByBlueprintKey[snackIdea.key],
              let eventIdeaID = ideaIDsByBlueprintKey[eventIdea.key],
              workspace.ideas.contains(where: {
                  $0.id == snackIdeaID && $0.category == .food && ($0.eventID ?? rootID) == rootID
              }),
              workspace.ideas.contains(where: {
                  $0.id == eventIdeaID && $0.category == .event && ($0.eventID ?? rootID) == rootID
              }) else {
            throw FactoryError.invalidBlueprint
        }
        return Workspace(planningWorkspace: workspace, snackIdeaID: snackIdeaID, eventIdeaID: eventIdeaID)
    }

    static func makeBundledWorkspace(
        account: UserAccount,
        bundle: Bundle = .main,
        today: Date = .now,
        timeZoneIdentifier: String = TimeZone.autoupdatingCurrent.identifier
    ) throws -> Workspace {
        guard let url = bundle.url(forResource: "movie-night-blueprint.v1", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            throw FactoryError.missingBundledBlueprint
        }
        return try makeWorkspace(account: account, localJSON: data, today: today, timeZoneIdentifier: timeZoneIdentifier)
    }
}

/// Installs or reopens the account's durable local lesson. Replays preserve an
/// active plan; completed tours start a fresh copy so the person can repeat it.
@MainActor
enum MovieNightTourCoordinator {
    enum StartError: Error {
        case wrongAccount
        case unavailable
    }

    @discardableResult
    static func startOrResume(
        account: UserAccount,
        library: WorkspaceLibrary,
        persistence: WorkspacePersistenceController,
        store: MovieNightTourStore? = nil,
        localJSON: Data? = nil,
        today: Date = .now
    ) throws -> PlanningWorkspace {
        guard persistence.activeUserID == account.id else { throw StartError.wrongAccount }
        let store = store ?? MovieNightTourStore()
        library.configureViewer(account)
        let progress = store.progress(accountID: account.id)
        if let progress,
           let existing = library.workspaces.first(where: { $0.mainEventID == progress.installedWorkspaceID }) {
            guard let viewer = existing.currentViewerMember(for: .main),
                  viewer.userID == account.id, viewer.participantRole == .host,
                  viewer.planningPermission == .manage,
                  viewer.invitationStatus == .active else { throw StartError.unavailable }
            let canResumeExisting = !existing.isMainEventDeleted
                && !existing.isScopedEvent
                && !existing.isInvitationProjection
                && !existing.currentMainEventStatus.isReadOnly
                && progress.step != .completed
            if canResumeExisting,
               let snackID = progress.snackIdeaID, let eventID = progress.eventIdeaID,
               let snackIdea = existing.ideas.first(where: {
                   $0.id == snackID && $0.category == .food
                       && ($0.eventID ?? existing.mainEventID) == existing.mainEventID
               }),
               let eventIdea = existing.ideas.first(where: {
                   $0.id == eventID && $0.category == .event
                       && $0.eventConfiguration != nil
                       && ($0.eventID ?? existing.mainEventID) == existing.mainEventID
               }),
               (existing.canScheduleEventIdea(eventIdea)
                   || existing.timeline.contains(where: {
                       $0.linkedIdeaID == eventIdea.id
                           && $0.parentEventID == existing.mainEventID
                           && $0.status == .approved
                           && $0.schedulingState != .unscheduled
                   })) {
                library.open(existing)
                store.restart(accountID: account.id, installedWorkspaceID: existing.mainEventID,
                              snackIdeaID: snackIdea.id, eventIdeaID: eventIdea.id)
                return existing
            }
            // Deleted, completed, read-only, or missing-target lessons fall
            // through to a new local plan. Existing content stays untouched.
        }
        let bundled: BundledMovieNightTour.Workspace
        if let localJSON {
            bundled = try BundledMovieNightTour.makeWorkspace(account: account, localJSON: localJSON, today: today)
        } else {
            bundled = try BundledMovieNightTour.makeBundledWorkspace(account: account, today: today)
        }
        let previouslySelectedWorkspace = library.selectedWorkspace
        library.add(bundled.planningWorkspace)
        do {
            try persistence.saveChanges(in: library)
        } catch {
            library.remove(bundled.planningWorkspace)
            if let previouslySelectedWorkspace,
               library.workspaces.contains(where: { $0.mainEventID == previouslySelectedWorkspace.mainEventID }) {
                library.open(previouslySelectedWorkspace)
            }
            throw error
        }
        store.restart(
            accountID: account.id,
            installedWorkspaceID: bundled.planningWorkspace.mainEventID,
            snackIdeaID: bundled.snackIdeaID,
            eventIdeaID: bundled.eventIdeaID
        )
        return bundled.planningWorkspace
    }
}
