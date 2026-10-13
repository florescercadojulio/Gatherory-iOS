import Foundation

/// Centralized, reusable product language.
///
/// SwiftUI automatically extracts literal text into the String Catalog. Copy
/// that also appears in models, filters, menus, or more than one feature lives
/// here so every surface resolves the same localized phrase.
enum AppCopy {
    enum Tab {
        static var home: String { localized("tab.home", default: "Home") }
        static var ideas: String { localized("tab.ideas", default: "Ideas") }
        static var decide: String { localized("tab.decide", default: "Decide") }
        static var insights: String { localized("tab.insights", default: "Insights") }
    }

    enum Common {
        static var add: String { localized("common.add", default: "Add") }
        static var back: String { localized("common.back", default: "Back") }
        static var cancel: String { localized("common.cancel", default: "Cancel") }
        static var close: String { localized("common.close", default: "Close") }
        static var continueAction: String { localized("common.continue", default: "Continue") }
        static var delete: String { localized("common.delete", default: "Delete") }
        static var done: String { localized("common.done", default: "Done") }
        static var edit: String { localized("common.edit", default: "Edit") }
        static var next: String { localized("common.next", default: "Next") }
        static var notNow: String { localized("common.notNow", default: "Not Now") }
        static var retry: String { localized("common.retry", default: "Try Again") }
        static var save: String { localized("common.save", default: "Save") }
    }

    enum Account {
        static var planner: String { localized("account.role.planner", default: "Planner") }
        static var member: String { localized("account.role.member", default: "Member") }
        static var apple: String { localized("account.provider.apple", default: "Apple") }
        static var google: String { localized("account.provider.google", default: "Google") }
        static var emailAndPassword: String {
            localized("account.provider.emailPassword", default: "Email and password")
        }
    }

    enum Appearance {
        static var system: String { localized("appearance.system", default: "System") }
        static var light: String { localized("appearance.light", default: "Light") }
        static var dark: String { localized("appearance.dark", default: "Dark") }
    }

    enum Planning {
        static var openToIdeas: String {
            localized("planning.mode.openToIdeas", default: "Open to Ideas")
        }
        static var helpMeDecide: String {
            localized("planning.mode.helpMeDecide", default: "Help Me Decide")
        }
        static var quietPlanning: String {
            localized("planning.mode.quietPlanning", default: "Quiet Planning")
        }
        static var decisionMade: String {
            localized("planning.mode.decisionMade", default: "Decision Made")
        }
        static var openToIdeasDetail: String {
            localized("planning.mode.openToIdeas.detail", default: "Your circle can send inspiration.")
        }
        static var helpMeDecideDetail: String {
            localized("planning.mode.helpMeDecide.detail", default: "Invite votes on selected options.")
        }
        static var quietPlanningDetail: String {
            localized("planning.mode.quietPlanning.detail", default: "Collect ideas without interruptions.")
        }
        static var decisionMadeDetail: String {
            localized("planning.mode.decisionMade.detail", default: "This planning topic is closed.")
        }
    }

    enum IdeaCategory {
        static var event: String { localized("idea.category.event", default: "Event") }
        static var registry: String { localized("idea.category.registry", default: "Registry") }
        static var link: String { localized("idea.category.link", default: "Link") }
        static var venue: String { localized("idea.category.venue", default: "Venue") }
        static var attire: String { localized("idea.category.attire", default: "Attire") }
        static var flowers: String { localized("idea.category.flowers", default: "Flowers") }
        static var food: String { localized("idea.category.food", default: "Food & Cake") }
        static var photography: String { localized("idea.category.photography", default: "Photography") }
        static var music: String { localized("idea.category.music", default: "Music") }
        static var decor: String { localized("idea.category.decor", default: "Decor") }
        static var invitations: String { localized("idea.category.invitations", default: "Invitations") }
        static var honeymoon: String { localized("idea.category.honeymoon", default: "Honeymoon") }
        static var other: String { localized("idea.category.other", default: "Other") }
    }

    enum IdeaStatus {
        static var new: String { localized("idea.status.new", default: "New") }
        static var maybe: String { localized("idea.status.maybe", default: "Maybe") }
        static var shortlisted: String { localized("idea.status.shortlisted", default: "Shortlisted") }
        static var approved: String { localized("idea.status.approved", default: "Approved") }
        static var passed: String { localized("idea.status.passed", default: "Passed") }
        static var archived: String { localized("idea.status.archived", default: "Archived") }
    }

    enum Attire {
        static var any: String { localized("attire.any", default: "Any") }
        static var blackTie: String { localized("attire.blackTie", default: "Black Tie") }
        static var formal: String { localized("attire.formal", default: "Formal") }
        static var cocktail: String { localized("attire.cocktail", default: "Cocktail") }
        static var garden: String { localized("attire.garden", default: "Garden") }
        static var casual: String { localized("attire.casual", default: "Casual") }
    }

    enum Food {
        static var meal: String { localized("food.type.meal", default: "Meal") }
        static var cake: String { localized("food.type.cake", default: "Cake") }
        static var dessert: String { localized("food.type.dessert", default: "Dessert") }
        static var drinks: String { localized("food.type.drinks", default: "Drinks") }
        static var tasting: String { localized("food.type.tasting", default: "Tasting") }
        static var other: String { localized("food.type.other", default: "Other") }
    }

    enum Primer {
        enum Onboarding {
            static var welcomeTitle: String {
                localized("primer.onboarding.welcome.title", default: "Welcome to Gatherory")
            }
            static var invitationTitle: String {
                localized("primer.onboarding.invitation.title", default: "Received an invitation?")
            }
            static var invitationMessage: String {
                localized(
                    "primer.onboarding.invitation.message",
                    default: "Open the link you were sent to view the event and respond."
                )
            }
            static var planningTitle: String {
                localized("primer.onboarding.planning.title", default: "Planning something?")
            }
            static var planningMessage: String {
                localized(
                    "primer.onboarding.planning.message",
                    default: "Create an event and bring everyone, every idea, and every detail together."
                )
            }
            static var collaborationMessage: String {
                localized(
                    "primer.onboarding.collaboration.message",
                    default: "Your event can include names, dates, locations, budgets, and participants. You decide who can join and collaborate."
                )
            }
            static var welcomeEyebrow: String {
                localized("primer.onboarding.create.eyebrow", default: "Welcome to")
            }
            static var createMessage: String {
                localized(
                    "primer.onboarding.create.message",
                    default: "Create a beautiful home for your event, then shape every plan with the people who matter."
                )
            }
            static var createEvent: String {
                localized("primer.onboarding.create.action", default: "Create an Event")
            }
            static var artworkAccessibilityLabel: String {
                localized(
                    "primer.onboarding.artwork.accessibilityLabel",
                    default: "Examples of event workspaces in Gatherory"
                )
            }
        }

        enum Decide {
            static var title: String {
                localized("primer.decide.title", default: "Decide what moves forward")
            }
            static var message: String {
                localized(
                    "primer.decide.message",
                    default: "Love an idea to approve it. Dated event ideas appear on Home, while ideas without a date stay here until you schedule them."
                )
            }
            static var datedTitle: String {
                localized("primer.decide.dated.title", default: "Already has a date")
            }
            static var datedDetail: String {
                localized("primer.decide.dated.detail", default: "It appears in Home with your events.")
            }
            static var undatedTitle: String {
                localized("primer.decide.undated.title", default: "Still needs a date")
            }
            static var undatedDetail: String {
                localized("primer.decide.undated.detail", default: "It stays in Ideas until you add a date.")
            }
            static var action: String {
                localized("primer.decide.action", default: "Start Deciding")
            }
        }

        enum Permission {
            static var eventLocation: String {
                localized("primer.permission.eventLocation", default: "Event location")
            }
        }
    }

    private static func localized(
        _ key: StaticString,
        default defaultValue: String.LocalizationValue
    ) -> String {
        String(localized: key, defaultValue: defaultValue)
    }
}
