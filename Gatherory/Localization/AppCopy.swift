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
    enum Home {
        static func daysAway(_ count: Int) -> String {
            count == 1
                ? String(localized: "home.daysAway.one", defaultValue: "1 day away")
                : String(localized: "home.daysAway.many", defaultValue: "\(count) days away")
        }
        static func peopleGoing(_ count: Int) -> String {
            count == 1
                ? String(localized: "home.peopleGoing.one", defaultValue: "1 person going")
                : String(localized: "home.peopleGoing.many", defaultValue: "\(count) people going")
        }
        static func peopleInvited(_ count: Int) -> String {
            count == 1
                ? String(localized: "home.peopleInvited.one", defaultValue: "1 person invited")
                : String(localized: "home.peopleInvited.many", defaultValue: "\(count) people invited")
        }
        static var planningAndScouting: String { String(localized: "event.purpose.planning", defaultValue: "Planning & Scouting") }
        static var partOfEvent: String { String(localized: "event.purpose.experience", defaultValue: "Part of the Event") }
    }
    enum EventStatus {
        static var draft: String { String(localized: "event.status.draft", defaultValue: "Draft") }
        static var approved: String { String(localized: "event.status.approved", defaultValue: "Approved") }
        static var notSure: String { String(localized: "event.status.notSure", defaultValue: "Not Sure") }
        static var rejected: String { String(localized: "event.status.rejected", defaultValue: "Rejected") }
        static var archived: String { String(localized: "event.status.archived", defaultValue: "Archived") }
        static var ongoing: String { String(localized: "event.status.ongoing", defaultValue: "Ongoing") }
        static var finished: String { String(localized: "event.status.finished", defaultValue: "Finished") }
    }
    enum Music {
        static func songCount(_ count: Int) -> String {
            count == 1
                ? String(localized: "idea.music.songCount.one", defaultValue: "1 song")
                : String(localized: "idea.music.songCount.many", defaultValue: "\(count) songs")
        }
        static var sharedPlaylist: String { String(localized: "idea.music.sharedPlaylist", defaultValue: "Shared playlist") }
        static func submittedBy(_ name: String) -> String {
            String(localized: "idea.submittedBy", defaultValue: "From \(name)")
        }
    }
    enum IdeaScope {
        static var allIdeas: String { String(localized: "All Ideas") }
        static func filtered(_ title: String) -> String {
            String(localized: "%@, filtered", defaultValue: "\(title), filtered")
        }
    }
    enum Calendar {
        static var add: String { String(localized: "calendar.add", defaultValue: "Add to Calendar") }
        static var copyExplanation: String { String(localized: "calendar.copyExplanation", defaultValue: "Saves a copy. Changes won’t sync.") }
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
        static var manage: String { localized("tab.manage", default: "Manage") }
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
            localized("event.removal.delete.message", default: "This removes the main event and its sub-events from planning Home, and deletes their costs and shared moments. This cannot be undone here.")
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

    enum DuplicateEvent {
        static var title: String { localized("event.duplicate.title", default: "Duplicate Event") }
        static var newEvent: String { localized("event.duplicate.newEvent", default: "New Event") }
        static var name: String { localized("event.duplicate.name", default: "Event name") }
        static var copiedContent: String {
            localized("event.duplicate.copiedContent", default: "The event details, schedule, and planning ideas are copied. Replies and decisions start fresh.")
        }
        static var excludedContent: String {
            localized("event.duplicate.excludedContent", default: "A new event starts with you as the host. Guests, collaborators, replies, votes, tasks, notes, expenses, photos, and event sharing links aren’t copied.")
        }
        static var unavailableTitle: String {
            localized("event.duplicate.unavailable.title", default: "Event Can’t Be Duplicated")
        }
        static var unavailableMessage: String {
            localized("event.duplicate.unavailable.message", default: "The event or your access changed. Review the latest event before trying again.")
        }
        static func initialTitle(_ title: String) -> String {
            "\(localized("event.duplicate.copyTitlePrefix", default: "Copy of")) \(title)"
        }
    }

    enum Account {
        static var eventAccessUnavailable: String {
            String(localized: "account.eventAccessUnavailable", defaultValue: "Gatherory can no longer access this event.")
        }
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
        static var eventScope: String { String(localized: "planning.eventScope", defaultValue: "Planning event") }
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
        enum AccountLoading {
            static var title: String { localized("primer.accountLoading.title", default: "Bringing it all together") }
            static var message: String { localized("primer.accountLoading.message", default: "Getting your events and invitations ready.") }
            static var status: String { localized("primer.accountLoading.status", default: "Preparing your account…") }
        }

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
                    default: "Examples of events in Gatherory"
                )
            }
        }

        enum Decide {
            static var title: String {
                String(localized: "primer.decide.title", defaultValue: "Help your team choose")
            }
            static var pass: String { String(localized: "Pass") }
            static var maybe: String { String(localized: "Maybe") }
            static var love: String { String(localized: "Love It") }
            static var passDetail: String {
                String(localized: "primer.decide.swipe.pass", defaultValue: "Swipe left if it’s not for you.")
            }
            static var maybeDetail: String {
                String(localized: "primer.decide.swipe.maybe", defaultValue: "Swipe up if you’re not sure.")
            }
            static var loveDetail: String {
                String(localized: "primer.decide.swipe.love", defaultValue: "Swipe right if you love it. Your input helps the host choose.")
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
