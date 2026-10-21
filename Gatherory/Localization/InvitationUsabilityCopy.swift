import Foundation

enum InvitationUsabilityCopy {
    static var loading: String {
        String(localized: "invitation.usability.loading", defaultValue: "Loading invitation…")
    }

    static var guestAccess: String {
        String(localized: "invitation.usability.guestAccess", defaultValue: "Attend and respond. Planning stays private.")
    }

    static var viewPlans: String {
        String(localized: "invitation.usability.viewPlans", defaultValue: "View the plans without making changes.")
    }

    static var contributePlans: String {
        String(localized: "invitation.usability.contributePlans", defaultValue: "Help with ideas, decisions, and shared plans.")
    }

    static var managePlans: String {
        String(localized: "invitation.usability.managePlans", defaultValue: "Help manage this event and its planning team.")
    }

    static var planningInvitation: String {
        String(localized: "invitation.usability.planningInvitation", defaultValue: "You’re invited to the planning team.")
    }

    static var awaitingApproval: String {
        String(localized: "invitation.usability.awaitingApproval", defaultValue: "Request sent")
    }

    static var awaitingApprovalMessage: String {
        String(localized: "invitation.usability.awaitingApprovalMessage", defaultValue: "The host will review your request before you can join.")
    }

    static var requestDeclined: String {
        String(localized: "invitation.usability.requestDeclined", defaultValue: "Request declined")
    }

    static var requestDeclinedMessage: String {
        String(localized: "invitation.usability.requestDeclinedMessage", defaultValue: "Contact the host if you think this was a mistake.")
    }

    static var hostApprovalRequired: String {
        String(localized: "invitation.usability.hostApprovalRequired", defaultValue: "Host approval required")
    }

    static var hostApprovalMessage: String {
        String(localized: "invitation.usability.hostApprovalMessage", defaultValue: "The host will review your request before access begins.")
    }

    static var closeInvitation: String {
        String(localized: "invitation.usability.closeInvitation", defaultValue: "Close Invitation")
    }

    static var dismissError: String {
        String(localized: "invitation.usability.dismissError", defaultValue: "Dismiss Error")
    }
}
