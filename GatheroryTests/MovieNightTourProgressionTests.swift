import Foundation
import Testing
@testable import Gatherory

@MainActor
struct MovieNightTourProgressionTests {
    @Test("Tour advances only after the matching workspace action")
    func actionDrivenProgression() {
        let snackIdeaID = UUID()
        let eventIdeaID = UUID()
        let unrelatedIdeaID = UUID()

        #expect(MovieNightTourProgression.nextStep(
            from: .ideas,
            snackIdeaID: snackIdeaID,
            eventIdeaID: eventIdeaID,
            availableIdeaIDs: [snackIdeaID, eventIdeaID],
            lovedIdeaIDs: [unrelatedIdeaID],
            chosenIdeaIDs: [snackIdeaID],
            linkedEventIdeaIDs: [eventIdeaID]
        ) == .ideas)

        #expect(MovieNightTourProgression.nextStep(
            from: .ideas,
            snackIdeaID: snackIdeaID,
            eventIdeaID: eventIdeaID,
            availableIdeaIDs: [snackIdeaID, eventIdeaID],
            lovedIdeaIDs: [snackIdeaID],
            chosenIdeaIDs: [],
            linkedEventIdeaIDs: []
        ) == .loveIt)

        #expect(MovieNightTourProgression.nextStep(
            from: .loveIt,
            snackIdeaID: snackIdeaID,
            eventIdeaID: eventIdeaID,
            availableIdeaIDs: [snackIdeaID, eventIdeaID],
            lovedIdeaIDs: [snackIdeaID],
            chosenIdeaIDs: [unrelatedIdeaID],
            linkedEventIdeaIDs: [eventIdeaID]
        ) == .loveIt)

        #expect(MovieNightTourProgression.nextStep(
            from: .loveIt,
            snackIdeaID: snackIdeaID,
            eventIdeaID: eventIdeaID,
            availableIdeaIDs: [snackIdeaID, eventIdeaID],
            lovedIdeaIDs: [snackIdeaID],
            chosenIdeaIDs: [snackIdeaID],
            linkedEventIdeaIDs: []
        ) == .approve)

        #expect(MovieNightTourProgression.nextStep(
            from: .approve,
            snackIdeaID: snackIdeaID,
            eventIdeaID: eventIdeaID,
            availableIdeaIDs: [snackIdeaID, eventIdeaID],
            lovedIdeaIDs: [snackIdeaID],
            chosenIdeaIDs: [snackIdeaID, eventIdeaID],
            linkedEventIdeaIDs: [unrelatedIdeaID]
        ) == .approve)

        #expect(!MovieNightTourProgression.canComplete(
            snackIdeaID: snackIdeaID, eventIdeaID: eventIdeaID,
            availableIdeaIDs: [snackIdeaID, eventIdeaID],
            lovedIdeaIDs: [snackIdeaID], chosenIdeaIDs: [snackIdeaID], linkedEventIdeaIDs: []
        ))

        #expect(MovieNightTourProgression.nextStep(
            from: .approve,
            snackIdeaID: snackIdeaID,
            eventIdeaID: eventIdeaID,
            availableIdeaIDs: [snackIdeaID, eventIdeaID],
            lovedIdeaIDs: [snackIdeaID],
            chosenIdeaIDs: [snackIdeaID],
            linkedEventIdeaIDs: [eventIdeaID]
        ) == .schedule)

        #expect(MovieNightTourProgression.canComplete(
            snackIdeaID: snackIdeaID, eventIdeaID: eventIdeaID,
            availableIdeaIDs: [snackIdeaID, eventIdeaID],
            lovedIdeaIDs: [snackIdeaID], chosenIdeaIDs: [snackIdeaID], linkedEventIdeaIDs: [eventIdeaID]
        ))
        #expect(MovieNightTourProgression.nextStep(
            from: .approve, snackIdeaID: snackIdeaID, eventIdeaID: eventIdeaID,
            availableIdeaIDs: [snackIdeaID, eventIdeaID],
            lovedIdeaIDs: [], chosenIdeaIDs: [snackIdeaID], linkedEventIdeaIDs: [eventIdeaID]
        ) == .ideas, "Undoing the personal response returns to Decide guidance.")
        #expect(!MovieNightTourProgression.canComplete(
            snackIdeaID: snackIdeaID, eventIdeaID: eventIdeaID,
            availableIdeaIDs: [snackIdeaID, eventIdeaID],
            lovedIdeaIDs: [snackIdeaID], chosenIdeaIDs: [], linkedEventIdeaIDs: [eventIdeaID]
        ), "A linked event alone cannot complete a tour with an unapproved snack.")

        #expect(MovieNightTourProgression.nextStep(
            from: .previewUsed, snackIdeaID: nil, eventIdeaID: eventIdeaID,
            availableIdeaIDs: [eventIdeaID], lovedIdeaIDs: [], chosenIdeaIDs: [], linkedEventIdeaIDs: []
        ) == .completed, "A customized-away target quietly ends education before the intro prompt.")
        #expect(MovieNightTourProgression.nextStep(
            from: .loveIt, snackIdeaID: snackIdeaID, eventIdeaID: eventIdeaID,
            availableIdeaIDs: [eventIdeaID], lovedIdeaIDs: [snackIdeaID],
            chosenIdeaIDs: [snackIdeaID], linkedEventIdeaIDs: [eventIdeaID]
        ) == .completed, "A deleted captured target quietly ends the guide.")
        #expect(!MovieNightTourProgression.canComplete(
            snackIdeaID: snackIdeaID, eventIdeaID: eventIdeaID,
            availableIdeaIDs: [snackIdeaID], lovedIdeaIDs: [snackIdeaID],
            chosenIdeaIDs: [snackIdeaID], linkedEventIdeaIDs: [eventIdeaID]
        ), "A missing event idea cannot produce a false success state.")
    }
}
