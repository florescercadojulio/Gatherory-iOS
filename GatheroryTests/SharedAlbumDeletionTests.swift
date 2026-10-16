import Foundation
import SwiftData
import Testing
@testable import Gatherory

@MainActor
struct SharedAlbumDeletionTests {
    @Test("Deleting an album photo requires its authenticated uploader and upload permission")
    func deletionRequiresUploaderAndPermission() {
        let eventID = UUID()
        let photo = EventMoment(
            eventID: eventID,
            imageData: Data([1]),
            addedBy: "Owner",
            addedByUserID: "owner-account"
        )

        #expect(AlbumDeletionPolicy.permitsDeletion(
            moment: photo, eventID: eventID, viewerUserID: "owner-account", hasGalleryUploadPermission: true
        ))
        #expect(!AlbumDeletionPolicy.permitsDeletion(
            moment: photo, eventID: eventID, viewerUserID: "owner-account", hasGalleryUploadPermission: false
        ))
        #expect(!AlbumDeletionPolicy.permitsDeletion(
            moment: photo, eventID: eventID, viewerUserID: "another-account", hasGalleryUploadPermission: true
        ))
        #expect(!AlbumDeletionPolicy.permitsDeletion(
            moment: photo, eventID: eventID, viewerUserID: nil, hasGalleryUploadPermission: true
        ))
    }

    @Test("Album deletion stays inside the selected event and supports legacy main-event moments")
    func deletionIsEventScoped() {
        let mainEventID = UUID()
        let childEventID = UUID()
        let childPhoto = EventMoment(
            eventID: childEventID,
            imageData: Data([1]),
            addedBy: "Owner",
            addedByUserID: "owner-account"
        )
        let legacyMainPhoto = EventMoment(
            imageData: Data([2]),
            addedBy: "Owner",
            addedByUserID: "owner-account"
        )

        #expect(AlbumDeletionPolicy.permitsDeletion(
            moment: childPhoto, eventID: childEventID, viewerUserID: "owner-account", hasGalleryUploadPermission: true
        ))
        #expect(!AlbumDeletionPolicy.permitsDeletion(
            moment: childPhoto, eventID: mainEventID, viewerUserID: "owner-account", hasGalleryUploadPermission: true
        ))
        #expect(AlbumDeletionPolicy.permitsDeletion(
            moment: legacyMainPhoto, eventID: mainEventID, viewerUserID: "owner-account", hasGalleryUploadPermission: true, legacyMainEventID: mainEventID
        ))
        #expect(!AlbumDeletionPolicy.permitsDeletion(
            moment: legacyMainPhoto, eventID: childEventID, viewerUserID: "owner-account", hasGalleryUploadPermission: true, legacyMainEventID: mainEventID
        ))
    }

    @Test("An active contributing collaborator can remove their own upload, while a guest cannot")
    func contributorCanRemoveOwnUploadButGuestCannot() {
        let uploaderAccount = account("uploader-account")
        let contributor = WorkspaceMember(
            userID: uploaderAccount.id,
            name: "Contributor",
            participantRole: .collaborator,
            initials: "C",
            planningPermission: .contribute
        )
        let photo = EventMoment(
            imageData: Data([1]),
            addedBy: contributor.name,
            addedByUserID: uploaderAccount.id
        )
        let contributingWorkspace = makeWorkspace(member: contributor, photo: photo)
        contributingWorkspace.configureViewer(uploaderAccount)
        #expect(contributingWorkspace.canDeleteEventMoment(photo, from: .main))

        let guestAccount = account("guest-account")
        let guest = WorkspaceMember(
            userID: guestAccount.id,
            name: "Guest",
            participantRole: .guest,
            initials: "G",
            planningPermission: .viewOnly
        )
        let guestWorkspace = makeWorkspace(member: guest, photo: photo)
        guestWorkspace.configureViewer(guestAccount)
        #expect(!guestWorkspace.canDeleteEventMoment(photo, from: .main))
    }

    @Test("An authorized local deletion produces an account-scoped offline tombstone")
    func deletionQueuesDurableAccountScopedTombstone() throws {
        let photo = EventMoment(
            imageData: Data([0x01]),
            addedBy: "Owner",
            addedByUserID: "owner-account"
        )
        let host = WorkspaceMember(
            userID: "owner-account",
            name: "Owner",
            participantRole: .host,
            initials: "O"
        )
        let workspace = PlanningWorkspace(
            title: "Album event",
            mainEventStartsAt: .now,
            venueName: "",
            location: "",
            planningMode: .openToIdeas,
            members: [host],
            ideas: [],
            timeline: [],
            eventMoments: [photo],
            registry: []
        )
        workspace.configureViewer(account("owner-account"))
        let before = WorkspaceArchiveV1(workspace: workspace)

        #expect(workspace.canDeleteEventMoment(photo, from: .main))
        #expect(workspace.deleteEventMoment(photo, from: .main))
        #expect(workspace.eventMoments.isEmpty)
        #expect(!workspace.deleteEventMoment(photo, from: .main))

        let after = WorkspaceArchiveV1(workspace: workspace)
        let context = try makeContext()
        try WorkspaceOutboxWriter(
            context: context,
            codec: WorkspaceArchiveCodec(),
            ownerUserID: "owner-account"
        ).coalesceEntityMutations(
            scopeID: after.mainEventID,
            previousArchive: before,
            archive: after,
            pendingMutations: []
        )
        try context.save()

        let persisted = try ModelContext(context.container).fetch(FetchDescriptor<PendingMutation>())
        let tombstone = try #require(persisted.first { $0.entityType == .moment && $0.entityID == photo.id })
        #expect(tombstone.operation == .delete)
        #expect(tombstone.payload.isEmpty)
        #expect(tombstone.scopeID == after.mainEventID)
        #expect(tombstone.ownerUserID == "owner-account")
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(
            schema: OfflineSyncSchema.schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: OfflineSyncSchema.schema, configurations: [configuration])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    @Test("Deletion checks the stored photo owner, not a stale or modified viewer copy")
    func storedOwnerWins() {
        let viewer = account("viewer")
        let member = WorkspaceMember(userID: viewer.id, name: "Host", participantRole: .host, initials: "H")
        let stored = EventMoment(imageData: Data([1]), addedBy: "Another person", addedByUserID: "other")
        let workspace = makeWorkspace(member: member, photo: stored)
        workspace.configureViewer(viewer)
        var modifiedCopy = stored
        modifiedCopy.addedByUserID = viewer.id
        #expect(!workspace.canDeleteEventMoment(modifiedCopy, from: .main))
        #expect(!workspace.deleteEventMoment(modifiedCopy, from: .main))
        #expect(workspace.eventMoments == [stored])
    }

    private func account(_ id: String) -> UserAccount {
        UserAccount(
            id: id,
            email: "\(id)@example.test",
            displayName: id,
            role: .planner,
            authenticationProvider: .password,
            createdAt: .now
        )
    }

    private func makeWorkspace(member: WorkspaceMember, photo: EventMoment) -> PlanningWorkspace {
        PlanningWorkspace(
            title: "Album event",
            mainEventStartsAt: .now,
            venueName: "",
            location: "",
            planningMode: .openToIdeas,
            members: [member],
            ideas: [],
            timeline: [],
            eventMoments: [photo],
            registry: []
        )
    }
}
