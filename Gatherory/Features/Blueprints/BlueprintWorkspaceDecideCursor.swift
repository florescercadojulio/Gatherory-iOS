/// Pure, key-based cursor for browsing a blueprint's authored idea sequence.
struct BlueprintWorkspaceDecideCursor: Equatable {
    private(set) var selectedKey: String?

    init(keys: [String]) {
        selectedKey = keys.first
    }

    func currentKey(in keys: [String]) -> String? {
        guard let selectedKey else { return keys.first }
        return keys.contains(selectedKey) ? selectedKey : keys.first
    }

    func index(in keys: [String]) -> Int? {
        guard let key = currentKey(in: keys) else { return nil }
        return keys.firstIndex(of: key)
    }

    mutating func reconcile(to keys: [String]) {
        if let selectedKey, keys.contains(selectedKey) { return }
        selectedKey = keys.first
    }

    @discardableResult
    mutating func move(by offset: Int, through keys: [String]) -> String? {
        guard let currentIndex = index(in: keys) else {
            selectedKey = nil
            return nil
        }

        let (nextIndex, overflow) = currentIndex.addingReportingOverflow(offset)
        guard !overflow, keys.indices.contains(nextIndex) else {
            reconcile(to: keys)
            return selectedKey
        }

        selectedKey = keys[nextIndex]
        return selectedKey
    }
}
