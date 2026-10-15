import Foundation
import Testing
@testable import Gatherory

struct ExperienceContractTests {
    @Test("iOS decodes the portable cabin-stay blueprint without UI instructions")
    func decodesCabinStayBlueprint() throws {
        let data = Data(
            #"""
            {
              "$schema": "https://schemas.gatherory.com/experience-blueprint/v1.json",
              "kind": "experience_blueprint",
              "schemaVersion": 1,
              "blueprint": {
                "id": "family-cabin-stay",
                "revision": 1,
                "name": "Family Cabin Stay"
              },
              "experienceDefaults": {
                "type": "property_stay",
                "timeZone": "America/Detroit"
              },
              "roles": [
                {
                  "key": "visitor",
                  "permissions": ["experience.view", "contributions.create"]
                }
              ],
              "modules": [
                {
                  "key": "journal",
                  "type": "private_journal",
                  "version": 1,
                  "required": false,
                  "config": {
                    "defaultVisibility": "participant_group",
                    "allowPhotos": true
                  }
                }
              ],
              "presentation": {
                "theme": "forest",
                "coverAssetId": null,
                "moduleOrder": ["journal"]
              }
            }
            """#.utf8
        )

        let blueprint = try JSONDecoder().decode(ExperienceBlueprintDocument.self, from: data)

        #expect(blueprint.supportsCurrentSchema)
        #expect(blueprint.experienceDefaults.type == "property_stay")
        #expect(blueprint.modules.first?.type == "private_journal")
        #expect(
            blueprint.modules.first?.configuration["defaultVisibility"]
                == .string("participant_group")
        )
        #expect(blueprint.presentation?.moduleOrder == ["journal"])
    }

    @Test("Participant-group visibility cannot omit its group identity")
    func validatesParticipantGroupVisibility() throws {
        #expect(throws: ExperienceContractError.self) {
            try ContributionVisibilityPolicy(scope: .participantGroup)
        }

        let visibility = try ContributionVisibilityPolicy(
            scope: .participantGroup,
            participantGroupID: "family_flores"
        )
        let encoded = try JSONEncoder().encode(visibility)
        let decoded = try JSONDecoder().decode(ContributionVisibilityPolicy.self, from: encoded)

        #expect(decoded == visibility)
    }

    @Test("Legacy remote sync payloads default to payload schema version one")
    func legacyRemotePayloadVersion() throws {
        let data = Data(
            #"""
            {
              "scopeID": "5CF54762-4A9A-49C3-B1E8-DF26D184AFBA",
              "payload": "e30=",
              "serverVersion": 1,
              "updatedAt": "2026-10-12T12:00:00Z"
            }
            """#.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let snapshot = try decoder.decode(RemoteWorkspaceSnapshot.self, from: data)
        #expect(snapshot.effectivePayloadSchemaVersion == 1)
    }

    @Test("Unsupported remote payload versions stop before materialization")
    @MainActor
    func rejectsUnsupportedRemotePayloadVersion() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        let snapshot = RemoteWorkspaceSnapshot(
            scopeID: UUID(),
            payloadSchemaVersion: 2,
            payload: Data(),
            serverVersion: 1,
            updatedAt: .now
        )

        do {
            try persistence.applyBootstrap([snapshot], to: library)
            Issue.record("Unsupported versions must be rejected before decoding the payload")
        } catch WorkspacePersistenceError.unsupportedSyncPayloadVersion(let version) {
            #expect(version == 2)
        }
    }
}
