import Foundation

enum BlueprintLibraryCategoryFilter {
    static func matches(
        selectedCategory: BlueprintBrowseCategory?,
        contentCategories: [BlueprintBrowseCategory]
    ) -> Bool {
        selectedCategory.map(contentCategories.contains) ?? true
    }

    static func usedTemplateCategory(experienceType: String?) -> BlueprintBrowseCategory {
        switch experienceType {
        case "wedding": .weddings
        case "birthday": .birthdays
        case "holiday": .holidays
        default: .events
        }
    }
}
