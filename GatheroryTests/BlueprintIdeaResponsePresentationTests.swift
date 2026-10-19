import Testing
@testable import Gatherory

@MainActor
struct BlueprintIdeaResponsePresentationTests {
    @Test("Preview responses use the workspace bar's personal response segments")
    func segments() {
        #expect(BlueprintIdeaResponsePresentation.summary(.love) == TeamResponseSummary(love: 1))
        #expect(BlueprintIdeaResponsePresentation.summary(.maybe) == TeamResponseSummary(maybe: 1))
        #expect(BlueprintIdeaResponsePresentation.summary(.pass) == TeamResponseSummary(pass: 1))
        #expect(BlueprintIdeaResponsePresentation.summary(nil) == TeamResponseSummary(unanswered: 1))
        for choice in DecisionChoice.allCases {
            #expect(BlueprintIdeaResponsePresentation.summary(choice).total == 1)
            #expect(!BlueprintIdeaResponsePresentation.title(choice).isEmpty)
        }
    }
}
