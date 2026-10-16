/// Presentation-only grouping. Never sort, filter or mutate authored content
/// while arranging it into horizontally swipeable pages.
enum BlueprintPreviewPages {
    static func events<Item>(_ items: [Item], accessibility: Bool = false) -> [[Item]] {
        pages(items, size: accessibility ? 2 : 4)
    }

    static func ideas<Item>(_ items: [Item]) -> [[Item]] {
        pages(items, size: 3)
    }

    private static func pages<Item>(_ items: [Item], size: Int) -> [[Item]] {
        stride(from: 0, to: items.count, by: size).map { start in
            Array(items[start..<min(start + size, items.count)])
        }
    }
}
