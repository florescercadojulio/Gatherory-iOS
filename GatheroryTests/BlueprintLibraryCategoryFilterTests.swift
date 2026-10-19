import Foundation
import Testing
@testable import Gatherory

@MainActor
struct BlueprintLibraryCategoryFilterTests {
    @Test("No selection includes every category, including uncategorized content")
    func allCategoriesDefault() {
        #expect(BlueprintLibraryCategoryFilter.matches(
            selectedCategory: nil,
            contentCategories: [.weddings]
        ))
        #expect(BlueprintLibraryCategoryFilter.matches(
            selectedCategory: nil,
            contentCategories: []
        ))
    }

    @Test("Draft membership matches any declared category")
    func multipleDraftCategories() {
        let categories: [BlueprintBrowseCategory] = [.weddings, .birthdays]
        #expect(BlueprintLibraryCategoryFilter.matches(
            selectedCategory: .birthdays,
            contentCategories: categories
        ))
        #expect(!BlueprintLibraryCategoryFilter.matches(
            selectedCategory: .holidays,
            contentCategories: categories
        ))
        #expect(!BlueprintLibraryCategoryFilter.matches(
            selectedCategory: .birthdays,
            contentCategories: []
        ))
    }

    @Test("Used template experience types map to the existing browse categories")
    func usedExperienceTypeMapping() {
        #expect(BlueprintLibraryCategoryFilter.usedTemplateCategory(experienceType: "wedding") == .weddings)
        #expect(BlueprintLibraryCategoryFilter.usedTemplateCategory(experienceType: "birthday") == .birthdays)
        #expect(BlueprintLibraryCategoryFilter.usedTemplateCategory(experienceType: "holiday") == .holidays)
    }

    @Test("Missing and unknown used template types fall back to Other Events")
    func usedExperienceTypeFallback() {
        #expect(BlueprintLibraryCategoryFilter.usedTemplateCategory(experienceType: nil) == .events)
        #expect(BlueprintLibraryCategoryFilter.usedTemplateCategory(experienceType: "future_type") == .events)
    }
}
