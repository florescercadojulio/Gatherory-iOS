import Foundation

enum GuestCopy {
    static var continueAsGuest: String { String(localized: "guest.continue", defaultValue: "Continue as Guest") }
    static var nameTitle: String { String(localized: "guest.nameTitle", defaultValue: "What should we call you?") }
    static var nameHelp: String { String(localized: "guest.nameHelp", defaultValue: "Use a name people will recognize.") }
    static var name: String { String(localized: "guest.name", defaultValue: "Your Name") }
    static var invalidName: String { String(localized: "guest.invalidName", defaultValue: "Enter a name up to 80 characters.") }
    static var deviceOnly: String { String(localized: "guest.deviceOnly", defaultValue: "Your plans are saved on this device. Sign in to save them to your account.") }
    static var signInToSave: String { String(localized: "guest.signInToSave", defaultValue: "Sign In to Save") }
    static var signInPreservesInfo: String { String(localized: "guest.signInPreservesInfo", defaultValue: "Your guest plans and invitations will be kept with your account.") }
    static var leave: String { String(localized: "guest.leave", defaultValue: "Leave Guest Mode") }
    static var exitTitle: String { String(localized: "guest.exitTitle", defaultValue: "Remove Guest Information?") }
    static var exitHelp: String { String(localized: "guest.exitHelp", defaultValue: "Your guest plans and saved invitations will be removed from this device. Sign in to keep them with your account.") }
    static var remove: String { String(localized: "guest.remove", defaultValue: "Remove from This Device") }
    static var stay: String { String(localized: "guest.stay", defaultValue: "Keep Using as Guest") }
    static var storageFailed: String { String(localized: "guest.storageFailed", defaultValue: "Your guest information couldn't be saved. It hasn't been removed. Try again.") }
    static var linking: String { String(localized: "guest.linking", defaultValue: "Saving Your Guest Information…") }
    static var linkingFailed: String { String(localized: "guest.linkingFailed", defaultValue: "Couldn't Save Guest Information") }
    static var finishSavingHelp: String { String(localized: "guest.finishSavingHelp", defaultValue: "Sign in to the account you started saving to. Your guest information is still on this device.") }
    static var linkingHelp: String { String(localized: "guest.linkingHelp", defaultValue: "Your guest information is still on this device. Try again to add it to your account.") }
    static var signInRequired: String { String(localized: "guest.signInRequired", defaultValue: "Sign In to Share") }
    static var shareHelp: String { String(localized: "guest.shareHelp", defaultValue: "Sign in to invite people or share your plans. Your guest plans will come with you.") }
    static var blueprintHelp: String { String(localized: "guest.blueprintHelp", defaultValue: "Sign in to save or share blueprints with your account.") }
    static var guestAccount: String { String(localized: "guest.account", defaultValue: "Guest") }
    static var joinAsGuest: String { String(localized: "guest.join", defaultValue: "Join as Guest") }
    static var attendAsGuest: String { String(localized: "guest.attend", defaultValue: "Attend as Guest") }
    static var joinHelp: String { String(localized: "guest.joinHelp", defaultValue: "Attend with your guest name. You can view the event and RSVP without an account.") }
    static var guestUnavailable: String { String(localized: "guest.unavailable", defaultValue: "This invitation requires sign-in. Your guest plans will stay on this device.") }
    static var publicGuestLinkHelp: String { String(localized: "guest.publicLinkHelp", defaultValue: "Guests can view the event and RSVP in the iPhone app without an account. Planning stays private.") }
    static var collaboratorLinkHelp: String { String(localized: "guest.collaboratorLinkHelp", defaultValue: "People sign in to help plan. You choose what they can change.") }
    static var collaboratorApprovalLinkHelp: String { String(localized: "guest.collaboratorApprovalLinkHelp", defaultValue: "People sign in to help plan. You approve requests before they can join.") }
    static var collaboratorViewOnlyLinkHelp: String { String(localized: "guest.collaboratorViewOnlyLinkHelp", defaultValue: "Sign in to view plans as a collaborator. This invitation provides view-only access.") }
    static var collaboratorViewOnlyApprovalLinkHelp: String { String(localized: "guest.collaboratorViewOnlyApprovalLinkHelp", defaultValue: "People sign in to view plans as collaborators. The host approves requests before access begins.") }
    static var signInToHelpPlan: String { String(localized: "guest.signInToHelpPlan", defaultValue: "Sign In to Help Plan") }
    static var signInToViewPlans: String { String(localized: "guest.signInToViewPlans", defaultValue: "Sign In to View Plans") }
    static var collaboratorSignInHelp: String { String(localized: "guest.collaboratorSignInHelp", defaultValue: "Sign in is required to accept this collaborator invitation. Planning access follows the selected permissions.") }
    static var emailInvitationSignInHelp: String { String(localized: "guest.emailInvitationSignInHelp", defaultValue: "Only the invited email address can accept this link, and sign-in is required. Share it using the options below; Gatherory does not send an email automatically.") }
}
