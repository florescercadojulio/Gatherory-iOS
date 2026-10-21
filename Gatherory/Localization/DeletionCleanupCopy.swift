import Foundation

enum DeletionCleanupCopy {
    static var deviceRemovalHelp: String { String(localized: "deletionCleanup.deviceRemovalHelp", defaultValue: "Removing this account’s saved information from this device. Other accounts and guest information will stay on this device.") }
    static var requestFailedTitle: String { String(localized: "deletionCleanup.requestFailedTitle", defaultValue: "Account Deletion Didn’t Finish") }
    static var requestFailedHelp: String { String(localized: "deletionCleanup.requestFailedHelp", defaultValue: "Your saved information has been kept. If you’re asked to sign in again, do that before trying to delete your account again.") }
    static var title: String { String(localized: "deletionCleanup.title", defaultValue: "Finishing Device Cleanup") }
    static var help: String { String(localized: "deletionCleanup.help", defaultValue: "Your account has been deleted. Some saved information still needs to be removed from this device. Try again to finish.") }
    static var waitingHelp: String { String(localized: "deletionCleanup.waitingHelp", defaultValue: "Waiting for account deletion to finish.") }
    static var unavailableHelp: String { String(localized: "deletionCleanup.unavailableHelp", defaultValue: "Gatherory couldn’t read its cleanup record. Your saved information hasn’t been replaced. Try again, or close and reopen the app.") }
    static var interruptedHelp: String { String(localized: "deletionCleanup.interruptedHelp", defaultValue: "The app was interrupted before account deletion could be confirmed. You can remove this account’s saved information from this device. This won’t send another account deletion request.") }
    static var removeFromDevice: String { String(localized: "deletionCleanup.removeFromDevice", defaultValue: "Remove from This Device") }
    static var removeTitle: String { String(localized: "deletionCleanup.removeTitle", defaultValue: "Remove This Account’s Device Data?") }
}
