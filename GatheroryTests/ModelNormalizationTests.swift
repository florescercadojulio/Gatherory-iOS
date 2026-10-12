import Foundation
import Testing
@testable import Gatherory

struct ModelNormalizationTests {
    @Test("Participant role and permission are scoped to one event")
    @MainActor
    func eventParticipationIsScoped() throws {
        let workspace = WeddingWorkspace.newWorkspace(
            title: "Wedding",
            startsAt: .now,
            eventLocation: nil,
            imageData: nil
        )
        workspace.inviteParticipant(
            name: "Taylor",
            initials: "T",
            role: .collaborator
        )
        let member = try #require(workspace.members.first { $0.name == "Taylor" })
        let child = TimelineItem(
            title: "Reception",
            category: .reception,
            purpose: .eventExperience,
            scheduledAt: .now,
            location: "",
            participantIDs: workspace.mainEventParticipantIDs,
            parentEventID: workspace.mainEventID
        )
        workspace.addTimelineItem(child)

        #expect(
            workspace.updateParticipant(
                member.id,
                role: .guest,
                planningPermission: .viewOnly,
                in: .subevent(child.id)
            )
        )

        let mainMember = try #require(
            workspace.participants(for: .main).first { $0.id == member.id }
        )
        let childMember = try #require(
            workspace.participants(for: .subevent(child.id)).first { $0.id == member.id }
        )
        #expect(mainMember.participantRole == .collaborator)
        #expect(mainMember.planningPermission == .contribute)
        #expect(childMember.participantRole == .guest)
        #expect(childMember.planningPermission == .viewOnly)
    }

    @Test("Idea context updates the participant relationship for its event")
    @MainActor
    func ideaContextUsesOwningEvent() throws {
        let workspace = WeddingWorkspace.newWorkspace(
            title: "Wedding",
            startsAt: .now,
            eventLocation: nil,
            imageData: nil
        )
        workspace.inviteParticipant(name: "Taylor", initials: "T", role: .collaborator)
        let member = try #require(workspace.members.first { $0.name == "Taylor" })
        let child = TimelineItem(
            title: "Reception",
            category: .reception,
            purpose: .eventExperience,
            scheduledAt: .now,
            location: "",
            participantIDs: workspace.mainEventParticipantIDs,
            parentEventID: workspace.mainEventID
        )
        workspace.addTimelineItem(child)
        let idea = WeddingIdea(
            eventID: child.id,
            title: "Live band",
            note: "",
            category: .music,
            submittedBy: "You"
        )
        workspace.addIdea(idea)

        #expect(workspace.removeParticipant(member.id, from: .idea(idea.id)))
        #expect(workspace.participants(for: .main).contains { $0.id == member.id })
        #expect(!workspace.participants(for: .subevent(child.id)).contains { $0.id == member.id })

        workspace.addParticipant(member.id, to: .idea(idea.id))
        #expect(workspace.participants(for: .subevent(child.id)).contains { $0.id == member.id })
    }

    @Test("Deleting an event cascades through its local aggregate")
    @MainActor
    func eventDeletionCascades() throws {
        let workspace = WeddingWorkspace.newWorkspace(
            title: "Wedding",
            startsAt: .now,
            eventLocation: nil,
            imageData: nil
        )
        let child = TimelineItem(
            title: "Dinner",
            category: .reception,
            purpose: .eventExperience,
            scheduledAt: .now,
            location: "",
            participantIDs: workspace.mainEventParticipantIDs,
            parentEventID: workspace.mainEventID
        )
        workspace.addTimelineItem(child)
        workspace.addIdea(
            WeddingIdea(
                eventID: child.id,
                title: "Menu",
                note: "",
                category: .food,
                submittedBy: "You"
            )
        )
        workspace.addRegistryItem(
            RegistryItem(
                eventID: child.id,
                title: "Dinner fund",
                note: "",
                category: .cashFund,
                price: 100
            )
        )

        workspace.deleteTimelineItem(child)

        #expect(!workspace.timeline.contains { $0.id == child.id })
        #expect(!workspace.ideas.contains { $0.eventID == child.id })
        #expect(!workspace.registry.contains { $0.eventID == child.id })
        #expect(!workspace.eventParticipations.contains { $0.eventID == child.id })
    }

    @Test("An event keeps one shared playlist and merges unique songs")
    @MainActor
    func eventMusicPlaylistIsUnique() throws {
        let workspace = WeddingWorkspace.newWorkspace(
            title: "Wedding",
            startsAt: .now,
            eventLocation: nil,
            imageData: nil
        )
        let firstTrack = musicTrack(id: "first", title: "First Dance")
        let secondTrack = musicTrack(id: "second", title: "Last Dance")

        workspace.addIdea(
            musicPlaylist(
                eventID: workspace.mainEventID,
                title: "First playlist",
                tracks: [firstTrack]
            )
        )
        workspace.addIdea(
            musicPlaylist(
                eventID: workspace.mainEventID,
                title: "Updated playlist",
                tracks: [firstTrack, secondTrack]
            )
        )

        let playlists = workspace.ideas.filter { $0.category == .music }
        let playlist = try #require(playlists.first)
        #expect(playlists.count == 1)
        #expect(playlist.musicTracks == [firstTrack, secondTrack])
        #expect(playlist.status == .chosen)
        #expect(playlist.isShownOnInvitation)
        #expect(playlist.estimatedCost == nil)

        var editedPlaylist = playlist
        editedPlaylist.configuration = .music(MusicIdeaConfiguration(tracks: [secondTrack]))
        workspace.updateIdea(editedPlaylist)
        #expect(workspace.musicPlaylist(for: workspace.mainEventID)?.musicTracks == [secondTrack])
    }

    @Test("The main event and a child event keep separate playlists")
    @MainActor
    func playlistsAreScopedByEvent() throws {
        let workspace = WeddingWorkspace.newWorkspace(
            title: "Wedding",
            startsAt: .now,
            eventLocation: nil,
            imageData: nil
        )
        let reception = TimelineItem(
            title: "Reception",
            category: .reception,
            purpose: .eventExperience,
            scheduledAt: .now,
            location: "",
            participantIDs: workspace.mainEventParticipantIDs,
            parentEventID: workspace.mainEventID
        )
        workspace.addTimelineItem(reception)

        workspace.addIdea(
            musicPlaylist(
                eventID: workspace.mainEventID,
                title: "Ceremony Playlist",
                tracks: [musicTrack(id: "ceremony", title: "Processional")]
            )
        )
        workspace.addIdea(
            musicPlaylist(
                eventID: reception.id,
                title: "Reception Playlist",
                tracks: [musicTrack(id: "reception", title: "Dance Song")]
            )
        )

        #expect(workspace.musicPlaylist(for: workspace.mainEventID)?.title == "Ceremony Playlist")
        #expect(workspace.musicPlaylist(for: reception.id)?.title == "Reception Playlist")
        #expect(workspace.ideas.filter { $0.category == .music }.count == 2)
    }

    private func musicPlaylist(
        eventID: UUID,
        title: String,
        tracks: [MusicTrack]
    ) -> WeddingIdea {
        WeddingIdea(
            eventID: eventID,
            title: title,
            note: "",
            category: .music,
            submittedBy: "You",
            configuration: .music(MusicIdeaConfiguration(tracks: tracks))
        )
    }

    private func musicTrack(id: String, title: String) -> MusicTrack {
        MusicTrack(
            providerID: .appleMusic,
            catalogID: id,
            title: title,
            artistName: "Artist",
            albumTitle: nil,
            artworkURL: nil,
            externalURL: nil,
            isrc: nil,
            duration: nil
        )
    }
}

