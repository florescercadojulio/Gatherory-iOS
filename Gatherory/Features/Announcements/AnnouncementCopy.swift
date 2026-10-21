import Foundation

enum AnnouncementCopy {
    static var planningTeam: String { String(localized: "announcements.planningTeam", defaultValue: "Planning Team") }
    static var to: String { String(localized: "announcements.to", defaultValue: "Audience") }
    static var all: String { String(localized: "announcements.all", defaultValue: "All") }
    static var planning: String { String(localized: "announcements.planning", defaultValue: "Planning") }
    static var guests: String { String(localized: "announcements.guests", defaultValue: "Guests") }
    static var allHelp: String { String(localized: "announcements.allHelp", defaultValue: "Visible to everyone with access to this event.") }
    static var planningHelp: String { String(localized: "announcements.planningHelp", defaultValue: "Visible to hosts and collaborators. Guests won’t see this update.") }
    static var guestsHelp: String { String(localized: "announcements.guestsHelp", defaultValue: "Visible to guests and hosts. Other collaborators won’t see this update.") }
    static var notificationHelp: String { String(localized: "announcements.notificationHelp", defaultValue: "Notification delivery depends on each person’s settings.") }
    static var localHelp: String { String(localized: "announcements.localHelp", defaultValue: "Saved in your plans on this device. Guests won’t see this update, and no notification is sent.") }
    static var localSaveFailed: String { String(localized: "announcements.localSaveFailed", defaultValue: "Your update couldn’t be saved. Your message is still here. Try again.") }
    static var openUpdates: String { String(localized: "announcements.openUpdates", defaultValue: "View event updates") }

    static func title(for audience: EventAnnouncementAudience) -> String {
        switch audience { case .all: all; case .planning: planning; case .guests: guests }
    }
    static func help(for audience: EventAnnouncementAudience) -> String {
        switch audience { case .all: allHelp; case .planning: planningHelp; case .guests: guestsHelp }
    }
    static var planningNote: String { String(localized: "announcements.planningNote", defaultValue: "Add a Planning Note") }
    static var requestConflict: String { String(localized: "announcements.requestConflict", defaultValue: "This send request was already used. Refresh updates to check what was sent, then edit your message before sending again.") }
    static var title: String { String(localized: "announcements.title", defaultValue: "Updates") }
    static var sendUpdate: String { String(localized: "announcements.sendUpdate", defaultValue: "Send Update") }
    static var send: String { String(localized: "announcements.send", defaultValue: "Send") }
    static var message: String { String(localized: "announcements.message", defaultValue: "Message") }
    static var emptyTitle: String { String(localized: "announcements.emptyTitle", defaultValue: "No Updates Yet") }
    static var emptyDetail: String { String(localized: "announcements.emptyDetail", defaultValue: "Updates from your host will appear here.") }
    static var loadFailed: String { String(localized: "announcements.loadFailed", defaultValue: "Updates couldn’t be refreshed. Check your connection and try again.") }
    static var sendFailed: String { String(localized: "announcements.sendFailed", defaultValue: "Your update hasn’t been confirmed. Your message is kept here. Check your connection, then tap Send to try again.") }
    static var accessDenied: String { String(localized: "announcements.accessDenied", defaultValue: "Updates aren’t available for this event with your current access.") }
    static var unavailable: String { String(localized: "announcements.unavailable", defaultValue: "Updates are available when you’re signed in or attending an invited event as a guest.") }
    static var tooLong: String { String(localized: "announcements.tooLong", defaultValue: "Keep your update to 750 characters or fewer.") }
    static var host: String { String(localized: "announcements.host", defaultValue: "Host") }
    static var sent: String { String(localized: "announcements.sent", defaultValue: "Update Sent") }
    static var latest: String { String(localized: "announcements.latest", defaultValue: "Latest Updates") }
}
