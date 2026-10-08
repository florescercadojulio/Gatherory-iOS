import SwiftUI

struct AccountView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appAppearance") private var appearance = AppAppearance.system.rawValue
    @AppStorage("planningNotifications") private var notificationsEnabled = true

    var body: some View {
        @Bindable var workspace = workspace

        Form {
            Section {
                HStack(spacing: AppTheme.Spacing.standard) {
                    Text(workspace.members.first?.initials ?? "A")
                        .font(.title2.bold())
                        .foregroundStyle(.black)
                        .frame(width: 64, height: 64)
                        .background(AppTheme.ColorToken.lilac, in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(workspace.members.first?.name ?? "Your account")
                            .font(.headline)
                        Text(workspace.members.first?.role ?? "Planning lead")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)

                Button("Edit profile", systemImage: "pencil") { }
            }

            Section("App settings") {
                Toggle("Planning notifications", systemImage: "bell.badge", isOn: $notificationsEnabled)

                Picker("Appearance", systemImage: "circle.lefthalf.filled", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
            }

            Section("Wedding workspace") {
                LabeledContent("Workspace", value: workspace.title)
                Toggle("Registry visible to guests", systemImage: "gift.fill", isOn: $workspace.isRegistryShared)

                NavigationLink {
                    SupportCircleView()
                } label: {
                    Label("Support circle", systemImage: "person.3.fill")
                }
            }

            Section {
                Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { }
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

private struct SupportCircleView: View {
    @Environment(WeddingWorkspace.self) private var workspace

    var body: some View {
        List(workspace.members) { member in
            HStack(spacing: AppTheme.Spacing.standard) {
                Text(member.initials)
                    .font(.subheadline.bold())
                    .foregroundStyle(.black)
                    .frame(width: 40, height: 40)
                    .background(AppTheme.ColorToken.pink, in: Circle())

                VStack(alignment: .leading) {
                    Text(member.name)
                    Text(member.role)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Support circle")
    }
}

#Preview {
    NavigationStack {
        AccountView()
            .environment(WeddingWorkspace.sample)
    }
}
