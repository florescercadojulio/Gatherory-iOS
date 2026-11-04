import UIKit
import Testing
@testable import Gatherory

private final class NavigationIdentifierSelectorOnlyObject: NSObject {
    @objc dynamic var accessibilityIdentifier: String? { "magnifyingglass" }
}

struct MovieNightTourTabTargetPolicyTests {
    @Test("Each tour tab target matches its native localized accessibility label")
    func matchesEachNativeTabLabel() throws {
        let targets: [(MovieNightTourTarget, String)] = [
            (.exploreTab, ExploreCopy.title),
            (.homeTab, AppCopy.Tab.home),
            (.ideasTab, AppCopy.Tab.ideas),
            (.decideTab, AppCopy.Tab.decide),
        ]

        for (target, label) in targets {
            #expect(MovieNightTourTabTargetPolicy.matches(label, target: target))
            let labels = try #require(MovieNightTourTabTargetPolicy.labels(for: target))
            #expect(labels == [label])
        }
    }

    @Test("Each tab target rejects missing and other native tab labels")
    func rejectsMissingAndMismatchedLabels() {
        let targets: [(MovieNightTourTarget, [String])] = [
            (.exploreTab, [AppCopy.Tab.home, AppCopy.Tab.ideas, AppCopy.Tab.decide]),
            (.homeTab, [ExploreCopy.title, AppCopy.Tab.ideas, AppCopy.Tab.decide]),
            (.ideasTab, [ExploreCopy.title, AppCopy.Tab.home, AppCopy.Tab.decide]),
            (.decideTab, [ExploreCopy.title, AppCopy.Tab.home, AppCopy.Tab.ideas]),
        ]

        for (target, unrelatedLabels) in targets {
            #expect(!MovieNightTourTabTargetPolicy.matches(nil, target: target))
            for label in unrelatedLabels {
                #expect(!MovieNightTourTabTargetPolicy.matches(label, target: target))
            }
        }
    }

    @Test("Non-tab tour targets have no native tab labels")
    func ignoresNonTabTargets() {
        #expect(MovieNightTourTabTargetPolicy.labels(for: .movieNightBlueprint) == nil)
        #expect(MovieNightTourTabTargetPolicy.labels(for: .discoveryDialog) == nil)
        #expect(MovieNightTourTabTargetPolicy.labels(for: .ideasFilter) == nil)
    }

    @Test("Accessibility container counts are bounded before indexing")
    func validatesAccessibilityElementCount() {
        #expect(MovieNightTourTabTargetPolicy.validatedElementCount(reported: 1) == 1)
        #expect(MovieNightTourTabTargetPolicy.validatedElementCount(reported: 32) == 32)
        #expect(MovieNightTourTabTargetPolicy.validatedElementCount(reported: 128) == 128)
        #expect(MovieNightTourTabTargetPolicy.validatedElementCount(reported: Int.max) == 0)
        #expect(MovieNightTourTabTargetPolicy.validatedElementCount(reported: -1) == 0)
        #expect(MovieNightTourTabTargetPolicy.validatedElementCount(reported: 129) == 0)
    }

    @Test("Native navigation fallback maps each tour tab to its localized label and system image identifier")
    func mapsNavigationControlDescriptors() throws {
        let expected: [(MovieNightTourTarget, String, String)] = [
            (.exploreTab, ExploreCopy.title, "magnifyingglass"),
            (.homeTab, AppCopy.Tab.home, "house.fill"),
            (.ideasTab, AppCopy.Tab.ideas, "sparkles.rectangle.stack.fill"),
            (.decideTab, AppCopy.Tab.decide, "rectangle.on.rectangle.angled"),
        ]
        for (target, label, imageIdentifier) in expected {
            let descriptor = try #require(MovieNightTourTabTargetPolicy.navigationControl(for: target))
            #expect(descriptor == MovieNightTourNavigationControl(
                label: label, systemImageIdentifier: imageIdentifier
            ))
            #expect(MovieNightTourTabTargetPolicy.matchesNavigationControl(
                label: label, identifier: imageIdentifier, traits: .button, target: target
            ))
        }

        let filter = try #require(MovieNightTourTabTargetPolicy.navigationControl(for: .ideasFilter))
        #expect(filter == MovieNightTourNavigationControl(
            label: String(localized: "Filter ideas", defaultValue: "Filter ideas"),
            systemImageIdentifier: "ideas.filter"
        ))
        #expect(MovieNightTourTabTargetPolicy.matchesNavigationControl(
            label: filter.label, identifier: filter.systemImageIdentifier,
            traits: .button, target: .ideasFilter
        ))
    }

    @Test("Native navigation fallback requires the exact label, image identifier, and button trait")
    func rejectsUnrelatedNavigationAccessibilityElements() {
        #expect(!MovieNightTourTabTargetPolicy.matchesNavigationControl(
            label: "Events", identifier: "magnifyingglass", traits: .button, target: .exploreTab
        ))
        #expect(!MovieNightTourTabTargetPolicy.matchesNavigationControl(
            label: ExploreCopy.title, identifier: "house.fill", traits: .button, target: .exploreTab
        ))
        #expect(!MovieNightTourTabTargetPolicy.matchesNavigationControl(
            label: ExploreCopy.title, identifier: "magnifyingglass", traits: .image, target: .exploreTab
        ))
        #expect(!MovieNightTourTabTargetPolicy.matchesNavigationControl(
            label: "Filter events", identifier: "ideas.filter", traits: .button, target: .ideasFilter
        ))
        #expect(!MovieNightTourTabTargetPolicy.matchesNavigationControl(
            label: "Filter ideas", identifier: "magnifyingglass", traits: .button, target: .ideasFilter
        ))
    }

    @Test("Public accessibility identifier getter works without protocol conformance")
    func readsPublicIdentifierGetterFromNSObject() {
        let object = NavigationIdentifierSelectorOnlyObject()
        #expect(!(object is UIAccessibilityIdentification))
        #expect(object.responds(to: #selector(getter: UIAccessibilityIdentification.accessibilityIdentifier)))
        #expect(MovieNightTourTabTargetPolicy.accessibilityIdentifier(for: object) == "magnifyingglass")
    }
}
