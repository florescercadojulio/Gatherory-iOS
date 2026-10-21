import SwiftUI

struct EventGuestListExportButton: View {
    let action: () -> Void

    var body: some View {
        Button("Export Guest List", systemImage: "square.and.arrow.up", action: action)
            .accessibilityHint("Export a CSV copy of names and RSVP statuses")
            .accessibilityIdentifier("event-export-guest-list")
    }
}
