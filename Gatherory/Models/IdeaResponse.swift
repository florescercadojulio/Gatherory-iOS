import Foundation
import CryptoKit

/// One independent response per account and idea. A nil choice retracts a vote.
struct IdeaResponse: Identifiable, Codable, Hashable {
    let id: UUID
    let ideaID: UUID
    let userID: String
    var choice: DecisionChoice?

    init(ideaID: UUID, userID: String, choice: DecisionChoice?) {
        self.id = Self.identifier(ideaID: ideaID, userID: userID)
        self.ideaID = ideaID
        self.userID = userID
        self.choice = choice
    }

    static func identifier(ideaID: UUID, userID: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data("idea-response:\(ideaID.uuidString.lowercased()):\(userID)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

struct TeamResponseSummary: Equatable {
    var love = 0
    var maybe = 0
    var pass = 0
    var unanswered = 0
    var total: Int { love + maybe + pass + unanswered }
    var responded: Int { love + maybe + pass }
}
