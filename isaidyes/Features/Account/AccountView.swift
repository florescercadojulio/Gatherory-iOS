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
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 54))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(AppTheme.ColorToken.accent)
                        .frame(width: 64, height: 64)

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
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(AppTheme.ColorToken.background)
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
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
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(AppTheme.ColorToken.accent, in: Circle())

                VStack(alignment: .leading) {
                    Text(member.name)
                    Text(member.role)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Text(member.attendance.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.ColorToken.background)
        .navigationTitle("Support circle")
    }
}

#Preview {
    NavigationStack {
        AccountView()
            .environment(WeddingWorkspace.sample)
    }
}
