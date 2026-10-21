import Foundation

enum SessionFlowCopy {
    static var restorationTitle: String { String(localized: "session.restoreTitle", defaultValue: "Couldn’t Restore Your Sign-in") }
    static var restorationHelp: String { String(localized: "session.restoreHelp", defaultValue: "Your saved information is still on this device. Check your connection and try again, or sign in to continue.") }
    static var removalTitle: String { String(localized: "session.removalTitle", defaultValue: "Guest Removal Didn’t Finish") }
    static var removalHelp: String { String(localized: "session.removalHelp", defaultValue: "Some guest information may already have been removed from this device. Try again to finish leaving guest mode.") }
    static var preparationHelp: String { String(localized: "session.preparationHelp", defaultValue: "Your saved information couldn’t be opened safely. Try again to continue.") }
    static var originalAccountHelp: String { String(localized: "session.originalAccountHelp", defaultValue: "These guest plans have already started saving to another account. Sign out and use that account to finish saving them.") }
}
