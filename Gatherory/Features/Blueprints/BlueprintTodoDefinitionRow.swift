import SwiftUI

/// A reusable task definition has no completion state until a workspace is created.
struct BlueprintTodoDefinitionRow: View {
    let title: String
    let websiteURL: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
            if let normalized = EventTodo.normalizedWebsiteURL(websiteURL),
               EventTodo.isValidWebsiteURL(normalized), let url = URL(string: normalized) {
                Link(destination: url) {
                    Label(TodoCopy.openWebsite, systemImage: "arrow.up.right.square")
                        .font(.subheadline)
                        .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
