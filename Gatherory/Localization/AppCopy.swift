import Foundation

/// Centralized, reusable product language.
///
/// SwiftUI automatically extracts literal text into the String Catalog. Copy
/// that also appears in models, filters, menus, or more than one feature lives
/// here so every surface resolves the same localized phrase.
enum AppCopy {
    enum Lifecycle {
        static var leaveFailed: String { String(localized: "event.leave.failed", defaultValue: "You haven’t left the event. Connect and try again.") }
        static var cancelled: String { String(localized: "event.cancelled", defaultValue: "Cancelled") }
        static var cancelledDetail: String { String(localized: "event.cancelled.detail", defaultValue: "The event was cancelled. Its history is kept, but attendance and planning are closed.") }
        static var cancelEvent: String { String(localized: "event.cancel", defaultValue: "Cancel Event") }
        static var cancelMessage: String { String(localized: "event.cancel.message", defaultValue: "The event will be marked cancelled for everyone after sync. Its details are kept. Guests can no longer respond. Existing calendar copies won’t be updated.") }
        static var leave: String { String(localized: "event.leave", defaultValue: "Leave Event") }
        static var leaveMessage: String { String(localized: "event.leave.message", defaultValue: "You’ll lose access to this invitation. The event and everyone else’s plans stay unchanged. You can join again with a valid invitation.") }
    }
    enum Calendar {
        static var add: String { String(localized: "calendar.add", defaultValue: "Add to Calendar") }
        static var copyExplanation: String { String(localized: "calendar.copyExplanation", defaultValue: "Saves a copy. Later changes in Gatherory won’t update your calendar.") }
    }
    enum Safety {
        static var personActionsHint: String { String(localized: "safety.personActionsHint", defaultValue: "Touch and hold a linked person for personal safety options.") }
        static var block: String { String(localized: "safety.block", defaultValue: "Block Person") }
        static var unblock: String { String(localized: "safety.unblock", defaultValue: "Unblock") }
        static var blockedPeople: String { String(localized: "safety.blockedPeople", defaultValue: "Blocked People") }
        static var blockedPerson: String { String(localized: "safety.blockedPerson", defaultValue: "Blocked person") }
        static var noBlockedPeople: String { String(localized: "safety.noBlockedPeople", defaultValue: "You haven’t blocked anyone.") }
        static var blockExplanation: String { String(localized: "safety.blockExplanation", defaultValue: "Blocked people’s content is hidden for you and new invitations between you are prevented. Blocking doesn’t remove anyone’s event access.") }
        static var blockWaiting: String { String(localized: "safety.blockWaiting", defaultValue: "Hidden on this device · Waiting to block on your account") }
        static var hide: String { String(localized: "safety.image.hide", defaultValue: "Hide Photo for Me") }
        static var report: String { String(localized: "safety.image.report", defaultValue: "Report Photo") }
        static var reportExplanation: String { String(localized: "safety.image.explanation", defaultValue: "This hides the photo for you and sends a report to Gatherory. Event hosts do not need to approve normal photo uploads.") }
        static var reason: String { String(localized: "safety.image.reason", defaultValue: "Reason") }
        static var detail: String { String(localized: "safety.image.detail", defaultValue: "Additional details (optional)") }
        static var submit: String { String(localized: "safety.image.submit", defaultValue: "Send Report") }
        static var sending: String { String(localized: "safety.image.sending", defaultValue: "Sending…") }
        static var failed: String { String(localized: "safety.image.failed", defaultValue: "Your report was not sent. Try again or contact support.") }
        static var hiddenLocally: String { String(localized: "safety.image.hiddenLocally", defaultValue: "The photo is hidden on this device. It could not be hidden on your other devices. Try again when connected.") }
        static var contact: String { String(localized: "safety.contact", defaultValue: "Support & Report a Concern") }
        static var inappropriate: String { String(localized: "safety.reason.inappropriate", defaultValue: "Inappropriate image") }
        static var harassment: String { String(localized: "safety.reason.harassment", defaultValue: "Harassment") }
        static var privacy: String { String(localized: "safety.reason.privacy", defaultValue: "Privacy concern") }
        static var other: String { String(localized: "safety.reason.other", defaultValue: "Other concern") }
    }
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

    enum EventRemoval {
        static var actions: String { localized("event.removal.actions", default: "Event Actions") }
        static var deleteTitle: String { localized("event.removal.delete", default: "Delete Event") }
        static var archiveTitle: String { localized("event.removal.archive", default: "Archive Event") }
        static var deleteMessage: String {
            localized("event.removal.delete.message", default: "This removes the draft main event and its sub-events from planning Home, and deletes their costs and shared moments. This cannot be undone here.")
        }
        static var archiveMessage: String {
            localized("event.removal.archive.message", default: "This removes the sub-event from shared planning Home. Its details, ideas, and costs are kept. This does not cancel the invitation or notify guests.")
        }
        static var unavailableTitle: String {
            localized("event.removal.unavailable.title", default: "Event Cannot Be Removed")
        }
        static var unavailableMessage: String {
            localized("event.removal.unavailable.message", default: "The event’s status or your access changed. Review the latest event before trying again.")
        }
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
                String(localized: "primer.decide.title", defaultValue: "Decide what moves forward")
            }
            static var message: String {
                String(localized:
                    "primer.decide.message",
                    defaultValue: "Explore ideas from every event. Pass, save one for later, or love it to move the plan forward."
                )
            }
            static var datedTitle: String {
                String(localized: "primer.decide.dated.title", defaultValue: "Already has a date")
            }
            static var datedDetail: String {
                String(localized: "primer.decide.dated.detail", defaultValue: "Approved event ideas appear on Home.")
            }
            static var undatedTitle: String {
                String(localized: "primer.decide.undated.title", defaultValue: "Still needs a date")
            }
            static var undatedDetail: String {
                String(localized: "primer.decide.undated.detail", defaultValue: "Event ideas stay in Ideas until you add a date.")
            }
            static var action: String {
                String(localized: "primer.decide.action", defaultValue: "Start Deciding")
            }
            static var pass: String { String(localized: "Pass") }
            static var maybe: String { String(localized: "Maybe") }
            static var love: String { String(localized: "Love It") }
            static var exampleTitle: String {
                String(localized: "primer.decide.example.title", defaultValue: "Welcome Dinner")
            }
            static var exampleEvent: String {
                String(localized: "primer.decide.example.event", defaultValue: "Weekend Together")
            }
            static var practiceLabel: String {
                String(localized: "primer.decide.practice.label", defaultValue: "Practice idea")
            }
            static var practiceInstruction: String {
                String(localized: "primer.decide.practice.instruction", defaultValue: "Try a swipe or tap a choice. Your real ideas won’t change.")
            }
            static var practiceAccessibilityHint: String {
                String(localized: "primer.decide.practice.accessibility", defaultValue: "Swipe left to pass, up to save for later, or right to approve. This is a practice idea and won’t change your plans.")
            }
            static var passFeedback: String {
                String(localized: "primer.decide.feedback.pass", defaultValue: "Passed. Keep exploring ideas.")
            }
            static var maybeFeedback: String {
                String(localized: "primer.decide.feedback.maybe", defaultValue: "Saved for later in Ideas.")
            }
            static var loveFeedback: String {
                String(localized: "primer.decide.feedback.love", defaultValue: "Approved. Dated event ideas appear on Home.")
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
