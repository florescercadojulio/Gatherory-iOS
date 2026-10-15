import Foundation

enum BlueprintCopy {
    static var suggestionConfirmation: String { String(localized: "blueprint.suggestionConfirmation", defaultValue: "Suggested dates use the main event’s calendar date and time zone. Confirm each date before including a sub-event.") }
    static var datesKept: String { String(localized: "blueprint.datesKept", defaultValue: "Your confirmed dates have been kept. Changing the time zone changes how they are displayed, not when they happen.") }
    static var loadingDates: String { String(localized: "blueprint.loadingDates", defaultValue: "Finding suggested dates…") }
    static var datesUnavailable: String { String(localized: "blueprint.datesUnavailable", defaultValue: "Suggested dates aren’t available. You can still choose dates manually.") }
    static var confirmedDate: String { String(localized: "blueprint.confirmedDate", defaultValue: "Confirmed date") }
    static var confirmDate: String { String(localized: "blueprint.confirmDate", defaultValue: "Confirm date") }
    static var useSuggestedDate: String { String(localized: "blueprint.useSuggestedDate", defaultValue: "Use suggested date") }
    static var repeatedTime: String { String(localized: "blueprint.repeatedTime", defaultValue: "This time occurs twice when the clocks change. Choose which occurrence you mean.") }
    static var nonexistentTime: String { String(localized: "blueprint.nonexistentTime", defaultValue: "The suggested local time doesn’t exist because the clocks change. Choose another time.") }
    static var starter: String { String(localized: "blueprint.starter", defaultValue: "Use Template") }
    static var title: String { String(localized: "blueprint.title", defaultValue: "Wedding") }
    static func defaultEventName(for name: String) -> String {
        String(format: String(localized: "blueprint.defaultEventName", defaultValue: "%@’s wedding"), name)
    }
    static var description: String {
        String(localized: "blueprint.description", defaultValue: "Start with a plan you can shape over time.")
    }
    static var mainEvent: String { String(localized: "blueprint.mainEvent", defaultValue: "Main event") }
    static var children: String { String(localized: "blueprint.children", defaultValue: "Optional sub-events") }
    static var ideas: String { String(localized: "blueprint.ideas", defaultValue: "Starter ideas") }
    static var review: String { String(localized: "blueprint.review", defaultValue: "Review plan") }
    static var reviewing: String { String(localized: "blueprint.reviewing", defaultValue: "Preparing review…") }
    static var install: String { String(localized: "blueprint.install", defaultValue: "Create event plan") }
    static var installing: String { String(localized: "blueprint.installing", defaultValue: "Creating…") }
    static var omitted: String { String(localized: "blueprint.omitted", defaultValue: "Not included") }
    static var childDateRequired: String {
        String(localized: "blueprint.childDateRequired", defaultValue: "Choose a date and time to include this sub-event.")
    }
    static var chooseDate: String { String(localized: "blueprint.chooseDate", defaultValue: "Choose date and time") }
    static var dateTime: String { String(localized: "blueprint.dateTime", defaultValue: "Date and time") }
    static var timeZone: String { String(localized: "blueprint.timeZone", defaultValue: "Time zone") }
    static var useDeviceTimeZone: String { String(localized: "blueprint.useDeviceTimeZone", defaultValue: "Use Device Time Zone") }
    static var deviceTimeZoneHint: String { String(localized: "blueprint.deviceTimeZoneHint", defaultValue: "Starts with your device’s time zone. Choose another if the event is elsewhere. Location access isn’t needed.") }
    static var eventName: String { String(localized: "blueprint.eventName", defaultValue: "Event name") }
    static var eventType: String { String(localized: "blueprint.eventType", defaultValue: "Event type") }
    static var eventPurpose: String { String(localized: "blueprint.eventPurpose", defaultValue: "Purpose") }
    static var parentEvent: String { String(localized: "blueprint.parentEvent", defaultValue: "Parent event") }
    static var category: String { String(localized: "blueprint.category", defaultValue: "Category") }
    static var status: String { String(localized: "blueprint.status", defaultValue: "Status") }
    static var target: String { String(localized: "blueprint.target", defaultValue: "For") }
    static var configuration: String { String(localized: "blueprint.configuration", defaultValue: "Configuration") }
    static var experienceType: String { String(localized: "blueprint.experienceType", defaultValue: "Experience type") }
    static var categoryOrder: String { String(localized: "blueprint.categoryOrder", defaultValue: "Category order") }
    static var planningSetup: String { String(localized: "blueprint.planningSetup", defaultValue: "Planning setup") }
    static var loadFailed: String { String(localized: "blueprint.loadFailed", defaultValue: "This blueprint isn’t available right now.") }
    static var clientUpgradeRequired: String {
        String(localized: "blueprint.clientUpgradeRequired", defaultValue: "Update Gatherory to sync this blueprint. Your pending changes remain saved and will retry after updating.")
    }
    static var workspaceNotInBootstrap: String {
        String(localized: "blueprint.workspaceNotInBootstrap", defaultValue: "The installed event is still being prepared. Retry to finish syncing it to this device.")
    }
    static var signInRequired: String { String(localized: "blueprint.signInRequired", defaultValue: "Sign in to use blueprints.") }
    static var retryInstall: String { String(localized: "blueprint.retryInstall", defaultValue: "Resume installation") }
    static var retrySameRequest: String {
        String(localized: "blueprint.retrySameRequest", defaultValue: "Retry this exact request")
    }
    static var pendingInstall: String { String(localized: "blueprint.pendingInstall", defaultValue: "An installation is waiting to finish") }
    static var finishPreviousInstall: String {
        String(localized: "blueprint.finishPreviousInstall", defaultValue: "Finish the previous creation before starting another. Its request is kept for a safe retry.")
    }
    static var nothingCreatedYet: String {
        String(localized: "blueprint.nothingCreatedYet", defaultValue: "Review is only a preview. Nothing is created or approved until you install the plan.")
    }
    static var omissionReason: String { String(localized: "blueprint.omissionReason", defaultValue: "Reason") }
}
