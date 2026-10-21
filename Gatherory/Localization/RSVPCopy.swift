import Foundation

enum RSVPCopy {
    static var title: String { String(localized: "rsvp.title", defaultValue: "Your Response") }
    static var sending: String { String(localized: "rsvp.sending", defaultValue: "Sending response…") }
    static var saved: String { String(localized: "rsvp.saved", defaultValue: "Response confirmed") }
    static var unconfirmed: String { String(localized: "rsvp.unconfirmed", defaultValue: "Your response hasn’t been confirmed. Try again.") }
    static func retry(_ response: EventResponse) -> String {
        let title = responseTitle(response)
        return String(localized: "rsvp.retry", defaultValue: "Send “\(title)” Again")
    }
    static var refresh: String { String(localized: "rsvp.refresh", defaultValue: "Refresh Event") }
    static var selected: String { String(localized: "Selected") }
    static var notSelected: String { String(localized: "Not selected") }

    static func responseTitle(_ response: EventResponse) -> String {
        switch response {
        case .going: String(localized: "Going")
        case .notSure: String(localized: "Not Sure")
        case .notGoing: String(localized: "Not Going")
        }
    }
}
