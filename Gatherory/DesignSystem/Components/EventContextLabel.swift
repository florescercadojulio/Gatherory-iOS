import SwiftUI

/// A compact, consistent reminder of which event receives new ideas and decisions.
struct EventContextLabel: View {
    let section: String
    let eventTitle: String

    var body: some View {
        VStack(spacing: 0) {
            Text(section)
                .font(.headline)

            Text(eventTitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(section) for \(eventTitle)")
    }
}
