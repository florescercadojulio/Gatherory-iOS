import Testing
@testable import Gatherory

struct BlueprintWorkspaceDecideCursorTests {
    @Test("Cursor starts at the first authored idea and stops at both ends")
    func authoredOrderAndBounds() {
        let keys = ["venue", "flowers", "music"]
        var cursor = BlueprintWorkspaceDecideCursor(keys: keys)

        #expect(cursor.currentKey(in: keys) == "venue")
        #expect(cursor.move(by: -1, through: keys) == "venue")
        #expect(cursor.move(by: 1, through: keys) == "flowers")
        #expect(cursor.move(by: 1, through: keys) == "music")
        #expect(cursor.move(by: 1, through: keys) == "music")
        #expect(cursor.index(in: keys) == 2)
    }

    @Test("Empty input has no selection and movement remains safe")
    func emptyInput() {
        var cursor = BlueprintWorkspaceDecideCursor(keys: [])

        #expect(cursor.currentKey(in: []) == nil)
        #expect(cursor.index(in: []) == nil)
        #expect(cursor.move(by: 1, through: []) == nil)
        #expect(cursor.selectedKey == nil)

        cursor.reconcile(to: ["first"])
        #expect(cursor.currentKey(in: ["first"]) == "first")
    }

    @Test("Removing the selected idea resets to the first remaining authored idea")
    func removalReconcilesSelection() {
        var cursor = BlueprintWorkspaceDecideCursor(keys: ["one", "two", "three"])
        #expect(cursor.move(by: 1, through: ["one", "two", "three"]) == "two")

        cursor.reconcile(to: ["three", "one"])

        #expect(cursor.selectedKey == "three")
        #expect(cursor.currentKey(in: ["three", "one"]) == "three")
        cursor.reconcile(to: [])
        #expect(cursor.selectedKey == nil)
    }

    @Test("Reordering retains the selected idea and movement follows its new authored position")
    func reorderRetainsSelection() {
        var cursor = BlueprintWorkspaceDecideCursor(keys: ["one", "two", "three"])
        #expect(cursor.move(by: 1, through: ["one", "two", "three"]) == "two")
        let reordered = ["three", "two", "one"]

        cursor.reconcile(to: reordered)

        #expect(cursor.currentKey(in: reordered) == "two")
        #expect(cursor.index(in: reordered) == 1)
        #expect(cursor.move(by: 1, through: reordered) == "one")
    }

    @Test("Moving the cursor never changes the source key sequence")
    func movementDoesNotMutateSource() {
        let sourceKeys = ["first", "second"]
        var cursor = BlueprintWorkspaceDecideCursor(keys: sourceKeys)

        #expect(cursor.move(by: 1, through: sourceKeys) == "second")
        #expect(sourceKeys == ["first", "second"])
        #expect(cursor.selectedKey == "second")
    }
}
